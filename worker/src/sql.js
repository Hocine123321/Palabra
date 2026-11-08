// A tiny SQL interface so the stores run on node:sqlite (tests) and Durable Object storage (Cloudflare).
// Sql = { all(query, ...params): object[], run(query, ...params): void, transaction(fn): T }

/** node:sqlite DatabaseSync -> Sql. Rows are copied to plain objects. */
export function nodeSqlite(db) {
  let depth = 0;
  return {
    all: (query, ...params) => db.prepare(query).all(...params).map((row) => ({ ...row })),
    run: (query, ...params) => {
      db.prepare(query).run(...params);
    },
    transaction(fn) {
      if (depth > 0) return fn();
      db.exec("BEGIN");
      depth++;
      try {
        const result = fn();
        db.exec("COMMIT");
        return result;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      } finally {
        depth--;
      }
    },
  };
}

/** Durable Object storage -> Sql. */
export function durableSql(storage) {
  return {
    all: (query, ...params) => storage.sql.exec(query, ...params).toArray(),
    run: (query, ...params) => {
      storage.sql.exec(query, ...params).toArray();
    },
    transaction: (fn) => storage.transactionSync(fn),
  };
}
