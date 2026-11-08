import { LIMITS } from "./limits.js";
import { checkRate, ensureRatesTable } from "./rate.js";
import { isB64url, isHex64, parseBearer, sha256Hex, timingSafeEqualHex } from "./auth.js";

const fail = (status, error) => ({ ok: false, status, error });
const LAST_SEEN_STEP = 60;

/** One mirror: its devices and sealed items. The server only ever sees ciphertext and token hashes. */
export class MirrorStore {
  constructor(sql, opts = {}) {
    this.sql = sql;
    this.now = opts.now ?? (() => Math.floor(Date.now() / 1000));
    this.limits = { ...LIMITS, ...(opts.limits ?? {}) };
  }

  init() {
    const { sql } = this;
    sql.run("CREATE TABLE IF NOT EXISTS devices (deviceId TEXT PRIMARY KEY, role TEXT NOT NULL, tokenHash TEXT NOT NULL, createdAt INTEGER NOT NULL, lastSeen INTEGER NOT NULL)");
    sql.run("CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, sealed TEXT NOT NULL, deleted INTEGER NOT NULL)");
    sql.run("CREATE INDEX IF NOT EXISTS items_seq ON items (seq)");
    sql.run("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL)");
    ensureRatesTable(sql);
  }

  /** Makes the owner device. Only once. */
  create({ deviceId, ownerTokenHash }) {
    if (!isB64url(deviceId, 1, 64) || !isHex64(ownerTokenHash)) return fail(400, "bad_request");
    if (this.sql.all("SELECT COUNT(*) AS n FROM devices")[0].n > 0) return fail(409, "already_created");
    const now = this.now();
    this.sql.transaction(() => {
      this.sql.run("INSERT INTO devices (deviceId, role, tokenHash, createdAt, lastSeen) VALUES (?, 'owner', ?, ?, ?)", deviceId, ownerTokenHash, now, now);
      this.sql.run("INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', 0)");
      this.sql.run("INSERT OR IGNORE INTO meta (key, value) VALUES ('bytes', 0)");
    });
    return { ok: true };
  }

  async authenticate(bearer, role) {
    const parsed = parseBearer(bearer);
    if (!parsed) return fail(401, "unauthorized");
    const hash = await sha256Hex(parsed.token);
    // Read the row only after the await, so a device removed meanwhile is already gone here.
    const row = this.sql.all("SELECT deviceId, role, tokenHash, lastSeen FROM devices WHERE deviceId = ?", parsed.deviceId)[0];
    // Always hash and compare, so a missing device costs the same as a wrong token.
    if (!row || !timingSafeEqualHex(hash, row.tokenHash)) return fail(401, "unauthorized");
    if (role && row.role !== role) return fail(403, "forbidden");
    const now = this.now();
    if (now - row.lastSeen >= LAST_SEEN_STEP) {
      this.sql.run("UPDATE devices SET lastSeen = ? WHERE deviceId = ?", now, row.deviceId);
    }
    return { ok: true, device: { deviceId: row.deviceId, role: row.role } };
  }

  async addDevice(bearer, { deviceId, tokenHash } = {}) {
    const auth = await this.authenticate(bearer, "owner");
    if (!auth.ok) return auth;
    if (!isB64url(deviceId, 1, 64) || !isHex64(tokenHash)) return fail(400, "bad_request");
    if (this.sql.all("SELECT 1 AS x FROM devices WHERE deviceId = ?", deviceId).length > 0) return fail(409, "device_exists");
    const browsers = this.sql.all("SELECT COUNT(*) AS n FROM devices WHERE role = 'browser'")[0].n;
    if (browsers >= this.limits.browserDevices) return fail(409, "too_many_devices");
    const now = this.now();
    this.sql.run("INSERT INTO devices (deviceId, role, tokenHash, createdAt, lastSeen) VALUES (?, 'browser', ?, ?, ?)", deviceId, tokenHash, now, now);
    return { ok: true };
  }

  async listDevices(bearer) {
    const auth = await this.authenticate(bearer);
    if (!auth.ok) return auth;
    const rows = this.sql.all("SELECT deviceId, role, createdAt, lastSeen FROM devices ORDER BY createdAt, deviceId");
    return {
      ok: true,
      devices: rows.map((r) => ({ deviceId: r.deviceId, role: r.role, createdAt: r.createdAt, lastSeen: r.lastSeen })),
    };
  }

  async removeDevice(bearer, deviceId) {
    const auth = await this.authenticate(bearer, "owner");
    if (!auth.ok) return auth;
    const row = this.sql.all("SELECT role FROM devices WHERE deviceId = ?", String(deviceId))[0];
    if (!row) return fail(404, "not_found");
    if (row.role === "owner") return fail(400, "owner_device");
    this.sql.run("DELETE FROM devices WHERE deviceId = ?", String(deviceId));
    return { ok: true };
  }

  /** Validates the whole batch first, then writes it in one transaction. */
  async putItems(bearer, items) {
    const auth = await this.authenticate(bearer, "owner");
    if (!auth.ok) return auth;
    const [limit, windowSec] = this.limits.rates.itemsPut;
    const rate = checkRate(this.sql, `put:${auth.device.deviceId}`, limit, windowSec, this.now());
    if (!rate.ok) return rate;

    if (!Array.isArray(items) || items.length === 0) return fail(400, "bad_request");
    if (items.length > this.limits.itemsPerPut) return fail(400, "too_many_items");
    const seen = new Set();
    const clean = [];
    for (const item of items) {
      if (!item || typeof item !== "object" || !isB64url(item.id, 16, 64) || seen.has(item.id)) return fail(400, "bad_request");
      seen.add(item.id);
      const deleted = item.deleted === true;
      const sealed = deleted ? "" : item.sealed;
      if (!deleted) {
        if (typeof sealed !== "string" || !/^[A-Za-z0-9_-]+$/.test(sealed)) return fail(400, "bad_request");
        if (sealed.length > this.limits.sealedChars) return fail(413, "too_large");
      }
      clean.push({ id: item.id, sealed, deleted });
    }

    const existing = new Set();
    for (const { id } of clean) {
      if (this.sql.all("SELECT 1 AS x FROM items WHERE id = ?", id).length > 0) existing.add(id);
    }
    const total = this.sql.all("SELECT COUNT(*) AS n FROM items")[0].n;
    if (total + (clean.length - existing.size) > this.limits.itemsTotal) return fail(409, "mirror_full");
    let replaced = 0;
    for (const id of existing) replaced += this.sql.all("SELECT length(sealed) AS n FROM items WHERE id = ?", id)[0].n;
    const added = clean.reduce((sum, c) => sum + c.sealed.length, 0);
    const bytes = this.meta("bytes") + added - replaced;
    if (bytes > this.limits.bytesTotal) return fail(409, "mirror_full");

    const seq = this.sql.transaction(() => {
      let next = this.meta("seq");
      for (const { id, sealed, deleted } of clean) {
        next += 1;
        this.sql.run("INSERT OR REPLACE INTO items (id, seq, sealed, deleted) VALUES (?, ?, ?, ?)", id, next, sealed, deleted ? 1 : 0);
      }
      this.sql.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('seq', ?)", next);
      this.sql.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('bytes', ?)", bytes);
      return next;
    });
    return { ok: true, seq };
  }

  async listItems(bearer, since, limit) {
    const auth = await this.authenticate(bearer);
    if (!auth.ok) return auth;
    const [rateLimit, windowSec] = this.limits.rates.itemsGet;
    const rate = checkRate(this.sql, `get:${auth.device.deviceId}`, rateLimit, windowSec, this.now());
    if (!rate.ok) return rate;
    if (!Number.isInteger(since) || since < 0) return fail(400, "bad_request");
    const n = Math.min(this.limits.listMax, Math.max(1, Math.floor(Number(limit)) || 1));

    // One extra row tells whether there is more.
    const rows = this.sql.all("SELECT id, seq, sealed, deleted FROM items WHERE seq > ? ORDER BY seq LIMIT ?", since, n + 1);
    const items = [];
    let chars = 0;
    let more = false;
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const overCount = items.length >= n;
      const overBytes = items.length > 0 && chars + row.sealed.length > this.limits.listSealedSoft;
      if (overCount || overBytes) {
        more = true;
        break;
      }
      items.push({ id: row.id, seq: row.seq, sealed: row.sealed, deleted: row.deleted === 1 });
      chars += row.sealed.length;
    }
    return { ok: true, items, seq: this.currentSeq(), more };
  }

  async state(bearer) {
    const auth = await this.authenticate(bearer);
    if (!auth.ok) return auth;
    return { ok: true, seq: this.currentSeq() };
  }

  meta(key) {
    return this.sql.all("SELECT value FROM meta WHERE key = ?", key)[0]?.value ?? 0;
  }

  currentSeq() {
    return this.meta("seq");
  }
}
