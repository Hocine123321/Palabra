import { test } from "node:test";
import assert from "node:assert/strict";
import { sha256Hex, randomId, parseBearer, timingSafeEqualHex, isHex64, isB64url } from "../src/auth.js";

test("sha256Hex of abc", async () => {
  assert.equal(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

test("parseBearer accepts deviceId.token", () => {
  assert.deepEqual(parseBearer("Bearer dev1.tok2"), { deviceId: "dev1", token: "tok2" });
});

test("parseBearer rejects malformed headers", () => {
  for (const bad of [null, "", "Bearer", "Bearer nodot", "Bearer a.b.c", "bearer a.b", "Bearer " + "a".repeat(300) + ".b", "Bearer a.b+c", "Bearer a.b/c", "Bearer a.b=", "Bearer a.bé", "Bearer é.b", "Bearer .b", "Bearer a."]) {
    assert.equal(parseBearer(bad), null, JSON.stringify(bad));
  }
});

test("randomId is 22 url-safe characters and distinct", () => {
  const seen = new Set();
  for (let i = 0; i < 1000; i++) {
    const id = randomId();
    assert.match(id, /^[A-Za-z0-9_-]{22}$/);
    seen.add(id);
  }
  assert.equal(seen.size, 1000);
});

test("timingSafeEqualHex", () => {
  assert.equal(timingSafeEqualHex("ab", "ab"), true);
  assert.equal(timingSafeEqualHex("ab", "ac"), false);
  assert.equal(timingSafeEqualHex("ab", "abc"), false);
});

test("isHex64", () => {
  assert.equal(isHex64("a".repeat(64)), true);
  assert.equal(isHex64("A".repeat(64)), false);
  assert.equal(isHex64("a".repeat(63)), false);
  assert.equal(isHex64("a".repeat(65)), false);
  assert.equal(isHex64(5), false);
});

test("isB64url honours the alphabet and the bounds", () => {
  assert.equal(isB64url("abc_-", 1, 10), true);
  assert.equal(isB64url("ab=", 1, 10), false);
  assert.equal(isB64url("", 1, 10), false);
  assert.equal(isB64url("a".repeat(11), 1, 10), false);
  assert.equal(isB64url(null, 1, 10), false);
});
