import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { encode, decode } from "../src/b64url.js";
import {
  CryptoFailure, deriveItemId, deriveKPair, generatePairKeys, importDataKey, matchCode, importDeviceKey, openItem, openRotation, openWrap, sealItem,
} from "../src/crypto.js";

const vectors = JSON.parse(readFileSync(new URL("../../PalabraTests/Mirroring/Fixtures/mirror-vectors.json", import.meta.url), "utf8"));
const fromHex = (h) => Uint8Array.from(Buffer.from(h, "hex"));
const text = (s) => new TextEncoder().encode(s);
const P = vectors.pair;

async function browserPrivateKey() {
  const pub = fromHex(P.browserPubHex);
  const jwk = { kty: "EC", crv: "P-256", x: encode(pub.slice(1, 33)), y: encode(pub.slice(33, 65)), d: encode(fromHex(P.browserPrivHex)) };
  return crypto.subtle.importKey("jwk", jwk, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
}

test("item id matches the vector", async () => {
  const keys = await importDataKey(fromHex(vectors.dataKeyHex));
  assert.equal(await deriveItemId(keys, vectors.id.kind, vectors.id.recordId), vectors.id.expected);
  assert.notEqual(await deriveItemId(keys, "deck", vectors.id.recordId), vectors.id.expected);
});

test("sealing reproduces the vector byte for byte and opens back", async () => {
  const keys = await importDataKey(fromHex(vectors.dataKeyHex));
  const sealed = await sealItem(keys, vectors.id.expected, text(vectors.item.plaintextUtf8), fromHex(vectors.item.ivHex));
  assert.equal(encode(sealed), vectors.item.expectedSealed);
  assert.equal(new TextDecoder().decode(await openItem(keys, vectors.id.expected, sealed)), vectors.item.plaintextUtf8);
});

test("a fresh iv is used when none is given", async () => {
  const keys = await importDataKey(fromHex(vectors.dataKeyHex));
  const a = await sealItem(keys, vectors.id.expected, text("x"));
  const b = await sealItem(keys, vectors.id.expected, text("x"));
  assert.notEqual(encode(a), encode(b));
});

test("any tampering, a different id or a short input is a CryptoFailure", async () => {
  const keys = await importDataKey(fromHex(vectors.dataKeyHex));
  const id = vectors.id.expected;
  const sealed = decode(vectors.item.expectedSealed);
  const flip = (i) => { const c = sealed.slice(); c[i] ^= 1; return c; };
  for (const [name, bad, useId] of [
    ["iv", flip(0), id], ["ciphertext", flip(14), id], ["tag", flip(sealed.length - 1), id],
    ["other id", sealed, deriveOther(id)], ["short", sealed.slice(0, 10), id], ["empty", new Uint8Array(0), id], ["28 bytes of nothing", new Uint8Array(28), id],
  ]) {
    await assert.rejects(openItem(keys, useId, bad), CryptoFailure, name);
  }
  const otherKeys = await importDataKey(new Uint8Array(32).fill(9));
  await assert.rejects(openItem(otherKeys, id, sealed), CryptoFailure, "other key");
});
const deriveOther = (id) => (id[0] === "A" ? "B" : "A") + id.slice(1);

test("a data key of the wrong length is refused", async () => {
  for (const n of [0, 16, 31, 33, 64]) await assert.rejects(importDataKey(new Uint8Array(n)), CryptoFailure, String(n));
});

test("the wrap opens with the browser key and the phone public key", async () => {
  const kPair = await deriveKPair(await browserPrivateKey(), fromHex(P.phonePubHex), fromHex(P.nonceHex));
  const wrap = await openWrap(kPair, P.pairId, decode(vectors.wrap.expectedSealed));
  assert.deepEqual([wrap.mirrorId, wrap.deviceId, wrap.deviceToken], ["MIRRORID", "DEVICEID", "TOKEN"]);
  assert.deepEqual(wrap.dataKey, fromHex(vectors.dataKeyHex));
  await assert.rejects(openWrap(kPair, "otherPairId", decode(vectors.wrap.expectedSealed)), CryptoFailure, "bound to the pair id");
  const tampered = decode(vectors.wrap.expectedSealed);
  tampered[20] ^= 1;
  await assert.rejects(openWrap(kPair, P.pairId, tampered), CryptoFailure);
});

test("the match code matches the vector and depends on every input", async () => {
  const b = fromHex(P.browserPubHex), p = fromHex(P.phonePubHex), n = fromHex(P.nonceHex);
  assert.equal(await matchCode(b, p, n), P.matchCode);
  assert.match(P.matchCode, /^\d{4}$/);
  const bump = (arr) => { const c = arr.slice(); c[c.length - 1] ^= 1; return c; };
  assert.notEqual(await matchCode(bump(b), p, n), P.matchCode);
  assert.notEqual(await matchCode(b, bump(p), n), P.matchCode);
  assert.notEqual(await matchCode(b, p, bump(n)), P.matchCode);
});

test("deriveKPair rejects malformed public keys and nonces", async () => {
  const priv = await browserPrivateKey();
  const pub = fromHex(P.phonePubHex);
  const nonce = fromHex(P.nonceHex);
  await assert.rejects(deriveKPair(priv, pub.slice(0, 64), nonce), CryptoFailure, "64 bytes");
  const compressedPrefix = pub.slice(); compressedPrefix[0] = 2;
  await assert.rejects(deriveKPair(priv, compressedPrefix, nonce), CryptoFailure, "prefix 0x02");
  const offCurve = pub.slice(); offCurve[64] ^= 1;
  await assert.rejects(deriveKPair(priv, offCurve, nonce), CryptoFailure, "not on the curve");
  await assert.rejects(deriveKPair(priv, pub, nonce.slice(0, 8)), CryptoFailure, "short nonce");
});

test("generatePairKeys gives an uncompressed point and a non-extractable private key", async () => {
  const { privateKey, publicRaw } = await generatePairKeys();
  assert.equal(publicRaw.length, 65);
  assert.equal(publicRaw[0], 4);
  await assert.rejects(crypto.subtle.exportKey("jwk", privateKey));
});

test("two fresh pairs agree on the same kPair", async () => {
  const a = await generatePairKeys();
  const b = await generatePairKeys();
  const nonce = crypto.getRandomValues(new Uint8Array(16));
  const ka = await deriveKPair(a.privateKey, b.publicRaw, nonce);
  const kb = await deriveKPair(b.privateKey, a.publicRaw, nonce);
  const iv = new Uint8Array(12);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, ka, text("hi")));
  assert.equal(new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, kb, ct)), "hi");
});

test("b64url is strict and round-trips", () => {
  for (const bad of ["ab=", "a+b", "a/b", "a b", "a"]) assert.throws(() => decode(bad), /bad base64url/, bad);
  for (let n = 0; n <= 40; n++) {
    const bytes = crypto.getRandomValues(new Uint8Array(n));
    const text = encode(bytes);
    assert.ok(!/[=+/]/.test(text));
    assert.deepEqual(decode(text), bytes);
  }
});

// MARK: Device keys and rotation

const R = vectors.rotation;
const rotationKey = () => importDeviceKey(fromHex(R.deviceKeyHex));

test("the rotation blob from the shared vector opens to the new data key", async () => {
  const out = await openRotation(await rotationKey(), R.mirrorId, R.deviceId, R.epoch, decode(R.expectedSealed));
  assert.deepEqual(out, { epoch: R.epoch, dataKey: fromHex(R.newDataKeyHex) });
});

test("a rotation blob fails for another mirror, device, epoch, device key, a flipped byte, a short input", async () => {
  const key = await rotationKey();
  const sealed = decode(R.expectedSealed);
  await assert.rejects(openRotation(key, "OTHER", R.deviceId, R.epoch, sealed), CryptoFailure);
  await assert.rejects(openRotation(key, R.mirrorId, "OTHER", R.epoch, sealed), CryptoFailure);
  await assert.rejects(openRotation(key, R.mirrorId, R.deviceId, R.epoch + 1, sealed), CryptoFailure);
  await assert.rejects(openRotation(key, R.mirrorId, R.deviceId, 0, sealed), CryptoFailure);
  await assert.rejects(openRotation(await importDeviceKey(new Uint8Array(32).fill(1)), R.mirrorId, R.deviceId, R.epoch, sealed), CryptoFailure);
  const flipped = sealed.slice();
  flipped[20] ^= 1;
  await assert.rejects(openRotation(key, R.mirrorId, R.deviceId, R.epoch, flipped), CryptoFailure);
  await assert.rejects(openRotation(key, R.mirrorId, R.deviceId, R.epoch, new Uint8Array(27)), CryptoFailure);
});

test("a blob whose inner epoch differs from the epoch it was sealed for is refused", async () => {
  const raw = fromHex(R.deviceKeyHex);
  const aesKey = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt"]);
  const iv = new Uint8Array(12).fill(9);
  const inner = new TextEncoder().encode(JSON.stringify({ v: 1, epoch: 99, dataKey: encode(fromHex(R.newDataKeyHex)) }));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: new TextEncoder().encode(`palabra-mirror-rotate-v1|${R.mirrorId}|${R.deviceId}|${R.epoch}`), tagLength: 128 }, aesKey, inner));
  const blob = new Uint8Array([...iv, ...ct]);
  await assert.rejects(openRotation(await rotationKey(), R.mirrorId, R.deviceId, R.epoch, blob), CryptoFailure);
});

test("the device key is not extractable", async () => {
  const key = await rotationKey();
  assert.equal(key.extractable, false);
  await assert.rejects(crypto.subtle.exportKey("raw", key));
});

test("a wrap with a deviceKey returns it, one without returns null, a wrong-sized one fails", async () => {
  const kPair = await deriveKPair(await browserPrivateKey(), fromHex(P.phonePubHex), fromHex(P.nonceHex));
  assert.equal((await openWrap(kPair, P.pairId, decode(vectors.wrap.expectedSealed))).deviceKey, null);
  const seal = async (body) => {
    const iv = new Uint8Array(12).fill(5);
    const key = await deriveKPair(await browserPrivateKey(), fromHex(P.phonePubHex), fromHex(P.nonceHex));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: new TextEncoder().encode(`palabra-mirror-wrap-v1|${P.pairId}`), tagLength: 128 }, key, new TextEncoder().encode(JSON.stringify(body))));
    return new Uint8Array([...iv, ...ct]);
  };
  const good = { v: 1, mirrorId: "M", deviceId: "D", deviceToken: "T", dataKey: encode(new Uint8Array(32)) };
  const withKey = await openWrap(kPair, P.pairId, await seal({ ...good, deviceKey: encode(new Uint8Array(32).fill(7)) }));
  assert.deepEqual(withKey.deviceKey, new Uint8Array(32).fill(7));
  await assert.rejects(openWrap(kPair, P.pairId, await seal({ ...good, deviceKey: encode(new Uint8Array(5)) })), CryptoFailure);
});
