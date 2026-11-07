import test from "node:test";
import assert from "node:assert/strict";
import {
  pairingProof, wrapSecret, unwrapSecret, roomId, Session, toHex, fromHex, randomBytes,
} from "../src/link-crypto.js";

const VECTORS = {
  proof: "f196d356ea14e5e4b5b1d6d0f5a3a8defebbb4f7e7e72a84b41515abddb846de",
  room: "378eb2daefa0d2b44fa98abda123fab0",
  wrapped: "0c72ab94a88039e2b8973938130fc537c30534d7914ee134dceb9f2ce955c823aeea7a7b37f149101df8342f3b64ed19",
};
const nonce = fromHex("000102030405060708090a0b0c0d0e0f");
const secret = fromHex("ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100");

test("right code gives the same proof, wrong code does not", async () => {
  const a = toHex(await pairingProof("482913", nonce));
  const b = toHex(await pairingProof("482913", nonce));
  const c = toHex(await pairingProof("482914", nonce));
  assert.equal(a, b);
  assert.notEqual(a, c);
});

test("the proof depends on the nonce", async () => {
  const other = fromHex("0f0e0d0c0b0a09080706050403020100");
  assert.notEqual(toHex(await pairingProof("482913", nonce)), toHex(await pairingProof("482913", other)));
});

test("wrapped secret opens with the code and only with the code", async () => {
  const { iv, ct } = await wrapSecret("482913", nonce, secret);
  assert.deepEqual(await unwrapSecret("482913", nonce, iv, ct), secret);
  await assert.rejects(unwrapSecret("000000", nonce, iv, ct));
  await assert.rejects(unwrapSecret("482913", fromHex("ff".repeat(16)), iv, ct));
});

test("room id is stable, 32 hex chars, and does not contain the secret", async () => {
  const id = await roomId(secret);
  assert.match(id, /^[0-9a-f]{32}$/);
  assert.equal(id, await roomId(secret));
  assert.ok(!toHex(secret).includes(id));
});

// Fixed vectors: the Swift side must reproduce these exactly (PalabraTests/WebLink/LinkCryptoTests.swift).
test("fixed vectors", async () => {
  assert.equal(toHex(await pairingProof("482913", nonce)), VECTORS.proof);
  assert.equal(await roomId(secret), VECTORS.room);
  const { ct } = await wrapSecret("482913", nonce, secret, fromHex("a0a1a2a3a4a5a6a7a8a9aaab"));
  assert.equal(toHex(ct), VECTORS.wrapped);
});

test("app and web talk both ways", async () => {
  const app = await Session.open(secret, "app");
  const web = await Session.open(secret, "web");
  assert.deepEqual(await web.open(await app.seal({ type: "ping", n: 1 })), { type: "ping", n: 1 });
  assert.deepEqual(await app.open(await web.seal({ type: "ack", n: 1 })), { type: "ack", n: 1 });
});

test("tampering, reflection, replay and a wrong secret are all rejected", async () => {
  const app = await Session.open(secret, "app");
  const web = await Session.open(secret, "web");
  const frame = await app.seal({ type: "ping" });
  const flipped = frame.slice(); flipped[frame.length - 1] ^= 1;
  await assert.rejects(web.open(flipped), /bad frame/);
  await assert.rejects(app.open(frame), /bad frame/);            // reflected back to its sender
  await web.open(frame);
  await assert.rejects(web.open(frame), /replayed/);              // same frame twice
  const stranger = await Session.open(randomBytes(32), "web");
  await assert.rejects(stranger.open(await app.seal({ type: "ping" })), /bad frame/);
});

test("frames are not readable and differ every time", async () => {
  const app = await Session.open(secret, "app");
  const f1 = await app.seal({ type: "ping", words: "secreto" });
  const f2 = await app.seal({ type: "ping", words: "secreto" });
  assert.notEqual(toHex(f1), toHex(f2));
  assert.ok(!Buffer.from(f1).toString("latin1").includes("secreto"));
});
