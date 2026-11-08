// Fixed-window counters in a `rates` table.

export function ensureRatesTable(sql) {
  sql.run("CREATE TABLE IF NOT EXISTS rates (key TEXT PRIMARY KEY, windowStart INTEGER NOT NULL, windowSec INTEGER NOT NULL, count INTEGER NOT NULL)");
}

/** Counts one hit for `key`. At most `limit` hits per `windowSec`. Opening a window also drops every expired counter. */
export function checkRate(sql, key, limit, windowSec, now) {
  const row = sql.all("SELECT windowStart, count FROM rates WHERE key = ?", key)[0];
  if (!row || now >= row.windowStart + windowSec) {
    sql.run("DELETE FROM rates WHERE windowStart + windowSec <= ?", now);
    sql.run("INSERT OR REPLACE INTO rates (key, windowStart, windowSec, count) VALUES (?, ?, ?, 1)", key, now, windowSec);
    return { ok: true };
  }
  if (row.count >= limit) {
    return { ok: false, status: 429, error: "rate_limited", retryAfter: Math.max(1, row.windowStart + windowSec - now) };
  }
  sql.run("UPDATE rates SET count = count + 1 WHERE key = ?", key);
  return { ok: true };
}
