import test from "node:test";
import assert from "node:assert/strict";
import { createCache, memoryStore, idbStore, SCHEMA } from "../src/cache.js";

const snap = { words: [{ id: "1", spanish: "hola" }] };

test("a saved snapshot comes back, a copy rather than the live object", async () => {
  const cache = createCache(memoryStore());
  assert.equal(await cache.loadSnapshot(), null);
  assert.equal(await cache.saveSnapshot(snap, "2026-11-07T10:00:00Z"), true);
  const back = await cache.loadSnapshot();
  assert.deepEqual(back, { snapshot: snap, takenAt: "2026-11-07T10:00:00Z" });
  back.snapshot.words.push({ id: "x" });
  assert.equal((await cache.loadSnapshot()).snapshot.words.length, 1);
});

test("a new snapshot replaces the old one entirely (no stale words survive)", async () => {
  const cache = createCache(memoryStore());
  await cache.saveSnapshot({ words: [{ id: "old" }] }, "t1");
  await cache.saveSnapshot({ words: [] }, "t2");
  assert.deepEqual(await cache.loadSnapshot(), { snapshot: { words: [] }, takenAt: "t2" });
});

test("data from another schema version, or damaged data, is ignored rather than misread", async () => {
  const store = memoryStore();
  const cache = createCache(store);
  await store.set("snapshot", { schema: SCHEMA + 1, snapshot: snap, takenAt: "t" });
  assert.equal(await cache.loadSnapshot(), null);
  await store.set("snapshot", { schema: SCHEMA, snapshot: null, takenAt: "t" });
  assert.equal(await cache.loadSnapshot(), null);
  await store.set("snapshot", "garbage");
  assert.equal(await cache.loadSnapshot(), null);
});

test("a browser that refuses storage (quota, private mode) never throws into the page", async () => {
  const broken = { get: async () => { throw new Error("denied"); }, set: async () => { throw new Error("quota"); }, delete: async () => { throw new Error("x"); }, keys: async () => { throw new Error("x"); } };
  const cache = createCache(broken);
  assert.equal(await cache.loadSnapshot(), null);
  assert.equal(await cache.saveSnapshot(snap, "t"), false);
  assert.equal(await cache.loadPairing(), null);
  assert.equal(await cache.savePairing({ secretHex: "ab", relayUrl: "wss://x" }), false);
  assert.equal(await cache.clearAll(), false);
});

test("pairing is remembered only when saved, needs both parts, and is gone after clearAll along with the data", async () => {
  const cache = createCache(memoryStore());
  assert.equal(await cache.loadPairing(), null);
  await cache.savePairing({ secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  await cache.saveSnapshot(snap, "t");
  assert.equal((await cache.loadPairing()).relayUrl, "wss://relay.example");
  await cache.clearAll();
  assert.equal(await cache.loadPairing(), null);
  assert.equal(await cache.loadSnapshot(), null);
});

test("an incomplete pairing record is not trusted", async () => {
  const store = memoryStore(); const cache = createCache(store);
  await store.set("pairing", { schema: SCHEMA, secretHex: "ab" });
  assert.equal(await cache.loadPairing(), null);
});

test("the IndexedDB store speaks the same interface (checked against a fake IndexedDB)", async () => {
  const data = new Map();
  const fakeIndexedDB = { open: () => {
    const req = {};
    queueMicrotask(() => {
      const store = (tx) => ({
        put: (v, k) => { data.set(k, structuredClone(v)); return {}; },
        get: (k) => ({ get result() { return data.get(k); } }),
        delete: (k) => { data.delete(k); return {}; },
        getAllKeys: () => ({ get result() { return [...data.keys()]; } }),
      });
      req.result = {
        createObjectStore() {},
        transaction() { const tx = {}; tx.objectStore = () => store(tx); queueMicrotask(() => queueMicrotask(() => tx.oncomplete?.())); return tx; },
        close() {},
      };
      req.onupgradeneeded?.(); req.onsuccess?.();
    });
    return req;
  } };
  const s = idbStore({ indexedDB: fakeIndexedDB });
  await s.set("a", { n: 1 });
  assert.deepEqual(await s.get("a"), { n: 1 });
  assert.deepEqual(await s.keys(), ["a"]);
  await s.delete("a");
  assert.equal(await s.get("a"), undefined);
});
