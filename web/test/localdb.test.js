import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { test } from "node:test";
import assert from "node:assert/strict";
import { openLocalDb } from "../src/localdb.js";
import { importDataKey } from "../src/crypto.js";

const fresh = () => openLocalDb(new IDBFactory());
const row = (n, kind = "word", g = 1) => ({ id: `id${n}`, kind, recordId: `r${n}`, g, d: { spanish: `palabra${n}` } });

test("credentials round-trip with usable non-extractable keys", async () => {
  const db = await fresh();
  assert.equal(await db.getCredentials(), null);
  const keys = await importDataKey(new Uint8Array(32).fill(3));
  await db.setCredentials({ mirrorId: "M", deviceId: "D", deviceToken: "T", keys });
  const got = await db.getCredentials();
  assert.deepEqual([got.mirrorId, got.deviceId, got.deviceToken], ["M", "D", "T"]);
  const iv = new Uint8Array(12);
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, got.keys.aes, new Uint8Array(4));
  assert.equal(ct.byteLength, 20);
  await assert.rejects(crypto.subtle.exportKey("raw", got.keys.aes));
});

test("applyPage writes rows, deletes ids and sets lastSeq together", async () => {
  const db = await fresh();
  assert.equal(await db.getLastSeq(), 0);
  await db.applyPage([row(1), row(2), row(3, "deck")], [], 3);
  assert.equal(await db.getLastSeq(), 3);
  assert.deepEqual((await db.itemsByKind("word")).map((r) => r.id).sort(), ["id1", "id2"]);
  assert.equal((await db.itemsByKind("deck")).length, 1);
  await db.applyPage([], ["id1"], 4);
  assert.equal(await db.getItem("id1"), undefined);
  assert.equal((await db.getItem("id2")).d.spanish, "palabra2");
});

test("a row with a lower generation never replaces a newer one", async () => {
  const db = await fresh();
  await db.applyPage([row(1, "word", 5)], [], 1);
  await db.applyPage([{ ...row(1, "word", 3), d: { spanish: "older" } }], [], 2);
  assert.equal((await db.getItem("id1")).d.spanish, "palabra1");
  await db.applyPage([{ ...row(1, "word", 6), d: { spanish: "newer" } }], [], 3);
  assert.equal((await db.getItem("id1")).d.spanish, "newer");
});

test("a failure in the middle of a page changes nothing", async () => {
  const db = await fresh();
  await db.applyPage([row(1)], [], 1);
  await assert.rejects(db.applyPage([row(2), { kind: "word", g: 1, d: {} } /* no id */], ["id1"], 9));
  assert.equal(await db.getLastSeq(), 1);
  assert.equal(await db.getItem("id2"), undefined);
  assert.ok(await db.getItem("id1"), "the delete was rolled back too");
});

test("clearAll empties credentials, items and the sequence", async () => {
  const db = await fresh();
  await db.setCredentials({ mirrorId: "M", deviceId: "D", deviceToken: "T", keys: await importDataKey(new Uint8Array(32)) });
  await db.applyPage([row(1)], [], 5);
  await db.clearAll();
  assert.equal(await db.getCredentials(), null);
  assert.equal(await db.getLastSeq(), 0);
  assert.deepEqual(await db.itemsByKind("word"), []);
});

test("allItems returns every row of every kind", async () => {
  const db = await fresh();
  await db.applyPage([row(1), row(2, "deck"), row(3, "manifest")], [], 3);
  assert.deepEqual((await db.allItems()).map((r) => r.id).sort(), ["id1", "id2", "id3"]);
});

test("getMeta and setMeta round-trip, and clearAll empties meta", async () => {
  const db = await fresh();
  assert.equal(await db.getMeta("x"), undefined);
  await db.setMeta("x", { a: 1 });
  assert.deepEqual(await db.getMeta("x"), { a: 1 });
  await db.clearAll();
  assert.equal(await db.getMeta("x"), undefined);
});

test("replaceEpoch swaps the credentials and drops every row and the sequence number together, keeping other meta", async () => {
  const db = await fresh();
  const oldKeys = await importDataKey(new Uint8Array(32).fill(3));
  await db.setCredentials({ mirrorId: "M", deviceId: "D", deviceToken: "T", keys: oldKeys, epoch: 0 });
  await db.applyPage([row(1), row(2)], [], 9);
  await db.setMeta("lang", "ar");

  const newKeys = await importDataKey(new Uint8Array(32).fill(4));
  await db.replaceEpoch({ mirrorId: "M", deviceId: "D", deviceToken: "T", keys: newKeys, epoch: 1 });

  assert.deepEqual(await db.allItems(), []);
  assert.equal(await db.getLastSeq(), 0);
  assert.equal(await db.getMeta("lang"), "ar");
  const got = await db.getCredentials();
  assert.equal(got.epoch, 1);
  // the stored key is the new one: it opens what the new key sealed
  const iv = new Uint8Array(12);
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, newKeys.aes, new Uint8Array([1]));
  assert.deepEqual(new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, got.keys.aes, ct)), new Uint8Array([1]));
});
