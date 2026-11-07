import test from "node:test";
import assert from "node:assert/strict";
import { makeTrustKeys, matchCode, sealGrant, openGrant, packGrant, unpackGrant, tokenHash, TOKEN_BYTES } from "../src/trust-crypto.js";
import { randomBytes, toHex } from "../src/link-crypto.js";

const grantOf = () => ({ secret: randomBytes(32), token: randomBytes(TOKEN_BYTES), relayUrl: "wss://palabra-relay.me.workers.dev" });

test("both ends show the same four digits, and the grant opens with the matching keys", async () => {
  const phone = await makeTrustKeys(), browser = await makeTrustKeys();
  const a = await matchCode(phone.pub, browser.pub), b = await matchCode(phone.pub, browser.pub);
  assert.match(a, /^\d{4}$/);
  assert.equal(a, b);
  const grant = grantOf();
  const box = await sealGrant({ phonePrivate: phone.privateKey, phonePub: phone.pub, browserPub: browser.pub, grant });
  const opened = await openGrant({ browserPrivate: browser.privateKey, phonePub: phone.pub, browserPub: browser.pub, ...box });
  assert.equal(toHex(opened.secret), toHex(grant.secret));
  assert.equal(toHex(opened.token), toHex(grant.token));
  assert.equal(opened.relayUrl, grant.relayUrl);
});

test("a man in the middle who swaps a public key gets a different code and cannot open the grant", async () => {
  const phone = await makeTrustKeys(), browser = await makeTrustKeys(), attacker = await makeTrustKeys();
  // The attacker tells the browser "I am the phone": the browser's view uses the attacker's key.
  assert.notEqual(await matchCode(phone.pub, browser.pub), await matchCode(attacker.pub, browser.pub));
  const box = await sealGrant({ phonePrivate: phone.privateKey, phonePub: phone.pub, browserPub: browser.pub, grant: grantOf() });
  await assert.rejects(openGrant({ browserPrivate: browser.privateKey, phonePub: attacker.pub, browserPub: browser.pub, ...box }));
  await assert.rejects(openGrant({ browserPrivate: attacker.privateKey, phonePub: phone.pub, browserPub: browser.pub, ...box }));
});

test("a changed byte in the grant is refused", async () => {
  const phone = await makeTrustKeys(), browser = await makeTrustKeys();
  const box = await sealGrant({ phonePrivate: phone.privateKey, phonePub: phone.pub, browserPub: browser.pub, grant: grantOf() });
  const flipped = box.sealed.slice(0, 10) + (box.sealed[10] === "0" ? "1" : "0") + box.sealed.slice(11);
  await assert.rejects(openGrant({ browserPrivate: browser.privateKey, phonePub: phone.pub, browserPub: browser.pub, iv: box.iv, sealed: flipped }));
});

test("keys that are not P-256 points are refused before any math", async () => {
  const browser = await makeTrustKeys();
  await assert.rejects(matchCode("00".repeat(65), browser.pub));
  await assert.rejects(matchCode("04", browser.pub));
  await assert.rejects(matchCode("zz", browser.pub));
});

test("the grant layout is secret, token, then the relay address, and a short one is refused", () => {
  const g = grantOf();
  const back = unpackGrant(packGrant(g));
  assert.equal(back.relayUrl, g.relayUrl);
  assert.throws(() => unpackGrant(new Uint8Array(10)));
  assert.throws(() => packGrant({ ...g, token: new Uint8Array(5) }));
  assert.equal(unpackGrant(packGrant({ ...g, relayUrl: "" })).relayUrl, "");
});

test("the token is stored as a hash that differs per token and is not the token", async () => {
  const t1 = randomBytes(32), t2 = randomBytes(32);
  assert.notEqual(await tokenHash(t1), await tokenHash(t2));
  assert.equal(await tokenHash(t1), await tokenHash(t1));
  assert.ok(!(await tokenHash(t1)).includes(toHex(t1)));
});

import { readFileSync } from "node:fs";
import { fromHex } from "../src/link-crypto.js";

test("the shared test vector still opens: this is what the Swift side must reproduce byte for byte", async () => {
  const v = JSON.parse(readFileSync(new URL("./trust-vector.json", import.meta.url), "utf8"));
  assert.equal(await matchCode(v.phonePub, v.browserPub), v.matchCode);
  const browserPrivate = await crypto.subtle.importKey("pkcs8", fromHex(v.browserPrivatePkcs8), { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const opened = await openGrant({ browserPrivate, phonePub: v.phonePub, browserPub: v.browserPub, iv: v.iv, sealed: v.sealed });
  assert.equal(toHex(opened.secret), v.secretHex);
  assert.equal(toHex(opened.token), v.tokenHex);
  assert.equal(opened.relayUrl, v.relayUrl);
});

test("the Swift test file carries the very same vector as the JSON fixture", () => {
  const v = JSON.parse(readFileSync(new URL("./trust-vector.json", import.meta.url), "utf8"));
  const swift = readFileSync(new URL("../../PalabraTests/WebLink/TrustCryptoTests.swift", import.meta.url), "utf8");
  for (const key of ["phonePrivatePkcs8", "phonePub", "browserPrivatePkcs8", "browserPub", "matchCode", "secretHex", "tokenHex", "relayUrl", "iv", "sealed"]) {
    assert.ok(swift.includes(`"${v[key]}"`), `Swift vector differs for ${key}`);
  }
});
