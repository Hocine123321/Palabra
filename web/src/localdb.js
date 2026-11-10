// The browser's own copy: credentials (with non-extractable CryptoKeys) and the opened items, in IndexedDB.

const DB_NAME = "palabra-mirror";
const VERSION = 1;

const wrap = (request) =>
  new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

/** Runs `work(tx)` in one transaction. If it throws or rejects, the whole transaction is rolled back. */
function run(db, stores, mode, work) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(stores, mode);
    let result;
    let failure = null;
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(failure ?? tx.error ?? new Error("transaction aborted"));
    work(tx).then(
      (value) => {
        result = value;
      },
      (error) => {
        failure = error;
        try {
          tx.abort();
        } catch {
          /* already finished */
        }
      },
    );
  });
}

export async function openLocalDb(idb = globalThis.indexedDB) {
  const db = await new Promise((resolve, reject) => {
    const request = idb.open(DB_NAME, VERSION);
    request.onupgradeneeded = () => {
      const created = request.result;
      created.createObjectStore("meta");
      created.createObjectStore("items", { keyPath: "id" }).createIndex("kind", "kind");
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  return {
    async getCredentials() {
      return (await run(db, ["meta"], "readonly", async (tx) => wrap(tx.objectStore("meta").get("creds")))) ?? null;
    },
    setCredentials(creds) {
      return run(db, ["meta"], "readwrite", async (tx) => {
        await wrap(tx.objectStore("meta").put(creds, "creds"));
      });
    },
    clearAll() {
      return run(db, ["meta", "items"], "readwrite", async (tx) => {
        await wrap(tx.objectStore("meta").clear());
        await wrap(tx.objectStore("items").clear());
      });
    },
    async getLastSeq() {
      return (await run(db, ["meta"], "readonly", async (tx) => wrap(tx.objectStore("meta").get("lastSeq")))) ?? 0;
    },
    /** Rows, deletions and the new sequence number land together or not at all. A row never replaces a newer generation. */
    applyPage(rows, deletes, lastSeq) {
      return run(db, ["meta", "items"], "readwrite", async (tx) => {
        const items = tx.objectStore("items");
        for (const row of rows) {
          if (typeof row?.id !== "string") throw new Error("row without an id");
          const existing = row.id ? await wrap(items.get(row.id)) : undefined;
          if (existing && existing.g > row.g) continue;
          await wrap(items.put(row));
        }
        for (const id of deletes) await wrap(items.delete(id));
        await wrap(tx.objectStore("meta").put(lastSeq, "lastSeq"));
      });
    },
    getItem(id) {
      return run(db, ["items"], "readonly", async (tx) => wrap(tx.objectStore("items").get(id)));
    },
    allItems() {
      return run(db, ["items"], "readonly", async (tx) => wrap(tx.objectStore("items").getAll()));
    },
    getMeta(key) {
      return run(db, ["meta"], "readonly", async (tx) => wrap(tx.objectStore("meta").get(key)));
    },
    setMeta(key, value) {
      return run(db, ["meta"], "readwrite", async (tx) => {
        await wrap(tx.objectStore("meta").put(value, key));
      });
    },
    itemsByKind(kind) {
      return run(db, ["items"], "readonly", async (tx) => wrap(tx.objectStore("items").index("kind").getAll(kind)));
    },
  };
}
