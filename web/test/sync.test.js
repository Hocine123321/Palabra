import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { test } from "node:test";
import assert from "node:assert/strict";
import { openLocalDb } from "../src/localdb.js";
import { AuthRevoked, pullOnce } from "../src/sync.js";
import { ApiError, OfflineError } from "../src/api.js";
import { deriveItemId, importDataKey, sealItem } from "../src/crypto.js";
import { encode } from "../src/b64url.js";

const utf8 = (s) => new TextEncoder().encode(s);

async function setup() {
  const keys = await importDataKey(new Uint8Array(32).fill(5));
  const db = await openLocalDb(new IDBFactory());
  await db.setCredentials({ mirrorId: "MIR", deviceId: "dev", deviceToken: "tok", keys });
  return { keys, db };
}

async function sealed(keys, { kind = "word", recordId, g = 1, d = {}, id }) {
  const itemId = id ?? (await deriveItemId(keys, kind, recordId));
  const plain = utf8(JSON.stringify({ v: 1, k: kind, r: recordId, h: "x", g, d }));
  return { id: itemId, sealed: encode(await sealItem(keys, itemId, plain)), deleted: false };
}

/** An api whose items() serves `list` ({id, seq, sealed, deleted}) in pages like the Worker. */
function fakeApi(list, { fail } = {}) {
  const calls = [];
  return {
    calls,
    items: async (mirrorId, bearer, since, limit = 200) => {
      calls.push({ mirrorId, bearer, since, limit });
      if (fail) throw fail;
      const rest = list.filter((i) => i.seq > since);
      const items = rest.slice(0, limit);
      return { items, seq: list.at(-1)?.seq ?? 0, more: rest.length > items.length };
    },
  };
}

test("pulls two pages, applies everything and remembers the last seq", async () => {
  const { keys, db } = await setup();
  const list = [];
  for (const [i, name] of ["uno", "dos", "tres"].entries()) list.push({ ...(await sealed(keys, { recordId: `r${i}`, d: { spanish: name } })), seq: i + 1 });
  const api = fakeApi(list);
  // limit 2 over 3 items: the page size is the api's choice, so force it small
  const small = { ...api, items: (m, b, s) => api.items(m, b, s, 2) };
  const result = await pullOnce({ api: small, db });
  assert.deepEqual(result, { applied: 3, deleted: 0, rejected: 0, seq: 3 });
  assert.equal(api.calls.length, 2);
  assert.equal(api.calls[0].bearer, "dev.tok");
  assert.equal(api.calls[1].since, 2, "continues from the last item's seq");
  assert.deepEqual((await db.itemsByKind("word")).map((r) => r.d.spanish).sort(), ["dos", "tres", "uno"]);
  assert.equal(await db.getLastSeq(), 3);
});

test("a second pull asks only for what is new", async () => {
  const { keys, db } = await setup();
  const list = [{ ...(await sealed(keys, { recordId: "a" })), seq: 1 }];
  await pullOnce({ api: fakeApi(list), db });
  const api2 = fakeApi(list);
  const result = await pullOnce({ api: api2, db });
  assert.equal(api2.calls[0].since, 1);
  assert.deepEqual(result, { applied: 0, deleted: 0, rejected: 0, seq: 1 });
});

test("a tombstone deletes the stored row", async () => {
  const { keys, db } = await setup();
  const item = await sealed(keys, { recordId: "a" });
  await pullOnce({ api: fakeApi([{ ...item, seq: 1 }]), db });
  assert.equal((await db.itemsByKind("word")).length, 1);
  const result = await pullOnce({ api: fakeApi([{ ...item, seq: 1 }, { id: item.id, sealed: "", deleted: true, seq: 2 }]), db });
  assert.equal(result.deleted, 1);
  assert.equal((await db.itemsByKind("word")).length, 0);
});

test("an item whose id does not match its own kind and record is rejected", async () => {
  const { keys, db } = await setup();
  const wrongId = await deriveItemId(keys, "word", "something-else");
  const liar = await sealed(keys, { recordId: "real", id: wrongId });
  const good = await sealed(keys, { recordId: "ok" });
  const result = await pullOnce({ api: fakeApi([{ ...liar, seq: 1 }, { ...good, seq: 2 }]), db });
  assert.deepEqual([result.applied, result.rejected], [1, 1]);
  assert.equal(await db.getItem(wrongId), undefined);
});

test("tampered or garbage items are rejected, not stored", async () => {
  const { keys, db } = await setup();
  const good = await sealed(keys, { recordId: "a" });
  const flipped = (() => { const t = good.sealed.split(""); t[20] = t[20] === "A" ? "B" : "A"; return t.join(""); })();
  const notJson = await (async () => {
    const id = await deriveItemId(keys, "word", "b");
    return { id, sealed: encode(await sealItem(keys, id, utf8("not json"))), deleted: false };
  })();
  const wrongShape = await sealed(keys, { recordId: "c", d: [] });
  const result = await pullOnce({
    api: fakeApi([{ ...good, sealed: flipped, seq: 1 }, { ...notJson, seq: 2 }, { ...wrongShape, seq: 3 }, { id: good.id, sealed: "no=pad", deleted: false, seq: 4 }]),
    db,
  });
  assert.deepEqual([result.applied, result.rejected], [0, 4]);
  assert.deepEqual(await db.itemsByKind("word"), []);
});

test("an older generation does not overwrite a newer stored row", async () => {
  const { keys, db } = await setup();
  const newer = await sealed(keys, { recordId: "a", g: 5, d: { spanish: "new" } });
  await pullOnce({ api: fakeApi([{ ...newer, seq: 1 }]), db });
  const older = await sealed(keys, { recordId: "a", g: 2, d: { spanish: "old" } });
  await pullOnce({ api: fakeApi([{ ...newer, seq: 1 }, { ...older, seq: 2 }]), db });
  assert.equal((await db.getItem(newer.id)).d.spanish, "new");
});

test("401 and 403 mean the computer was removed and store nothing", async () => {
  for (const status of [401, 403]) {
    const { db } = await setup();
    await assert.rejects(pullOnce({ api: fakeApi([], { fail: new ApiError(status, "unauthorized") }), db }), AuthRevoked);
    assert.equal(await db.getLastSeq(), 0);
  }
});

test("offline propagates and leaves the saved copy alone", async () => {
  const { keys, db } = await setup();
  const item = await sealed(keys, { recordId: "a" });
  await pullOnce({ api: fakeApi([{ ...item, seq: 1 }]), db });
  await assert.rejects(pullOnce({ api: fakeApi([], { fail: new OfflineError() }), db }), OfflineError);
  assert.equal((await db.itemsByKind("word")).length, 1);
  assert.equal(await db.getLastSeq(), 1);
});

test("pulling without credentials is an error", async () => {
  const db = await openLocalDb(new IDBFactory());
  await assert.rejects(pullOnce({ api: fakeApi([]), db }), /not paired/);
});
