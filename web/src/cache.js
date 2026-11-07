// Offline cache. The snapshot (and later, visited books and the latest chat) is kept in the browser so the page opens and
// works with the phone away. The phone stays the only real copy: this is a copy to read from, replaced on every sync.
//
// A `store` is any object with async get(key), set(key, value), delete(key), keys(). `idbStore()` is the real one;
// `memoryStore()` is for tests. Everything below works on that interface only.

export const SCHEMA = 1;                        // bump when the stored shape changes; old data is then ignored, not misread
const SNAPSHOT_KEY = "snapshot";
const PAIRING_KEY = "pairing";

export function memoryStore() {
  const map = new Map();
  return {
    get: async (k) => (map.has(k) ? structuredClone(map.get(k)) : undefined),
    set: async (k, v) => { map.set(k, structuredClone(v)); },
    delete: async (k) => { map.delete(k); },
    keys: async () => [...map.keys()],
  };
}

export function idbStore({ name = "palabra-web", indexedDB = globalThis.indexedDB } = {}) {
  const open = () => new Promise((resolve, reject) => {
    const req = indexedDB.open(name, 1);
    req.onupgradeneeded = () => req.result.createObjectStore("kv");
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  const run = async (mode, fn) => {
    const db = await open();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction("kv", mode);
        const request = fn(tx.objectStore("kv"));
        tx.oncomplete = () => resolve(request?.result);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  };
  return {
    get: (k) => run("readonly", (s) => s.get(k)),
    set: (k, v) => run("readwrite", (s) => s.put(v, k)),
    delete: (k) => run("readwrite", (s) => s.delete(k)),
    keys: () => run("readonly", (s) => s.getAllKeys()),
  };
}

/** What the page remembers between visits. All methods swallow storage failures into a plain "nothing saved". */
export function createCache(store) {
  const raw = store;
  const safe = async (fn, fallback) => { try { return await fn(); } catch { return fallback; } };
  return {
    /** The underlying store, for parts that keep their own record (the outbox). */
    store: raw,
    /** The last snapshot, or null if none (or one this version cannot read). */
    loadSnapshot: () => safe(async () => {
      const saved = await store.get(SNAPSHOT_KEY);
      return saved && saved.schema === SCHEMA && saved.snapshot && saved.takenAt ? { snapshot: saved.snapshot, takenAt: saved.takenAt } : null;
    }, null),
    /** Replaces the whole cached snapshot. Returns false if the browser refused (quota, private mode). */
    saveSnapshot: (snapshot, takenAt) => safe(async () => { await store.set(SNAPSHOT_KEY, { schema: SCHEMA, snapshot, takenAt }); return true; }, false),
    /** The paired phone's secret and addresses, so a reload reconnects without pairing again. */
    loadPairing: () => safe(async () => {
      const saved = await store.get(PAIRING_KEY);
      return saved && saved.schema === SCHEMA && typeof saved.secretHex === "string" && saved.relayUrl ? saved : null;
    }, null),
    savePairing: (pairing) => safe(async () => { await store.set(PAIRING_KEY, { schema: SCHEMA, ...pairing }); return true; }, false),
    /** "Forget this browser": removes the secret and every cached byte of the person's data. */
    clearAll: () => safe(async () => { for (const k of await store.keys()) await store.delete(k); return true; }, false),
  };
}
