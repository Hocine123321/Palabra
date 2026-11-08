import { LIMITS } from "./limits.js";
import { checkRate, ensureRatesTable } from "./rate.js";
import { isB64url, randomId } from "./auth.js";

const fail = (status, error) => ({ ok: false, status, error });
const PAIR_ID_CHARS = 22; // 16 random bytes, base64url
const PHONE_PUB_CHARS = 87; // 65-byte uncompressed P-256 point, base64url
const SEALED_MAX = 4096;
const LONGEST_RATE_WINDOW = 3600;

/** The singleton in front of everything: pairing slots and per-IP rate counters. Holds no keys, only opaque blobs. */
export class GateStore {
  constructor(sql, opts = {}) {
    this.sql = sql;
    this.now = opts.now ?? (() => Math.floor(Date.now() / 1000));
    this.limits = { ...LIMITS, ...(opts.limits ?? {}) };
  }

  init() {
    this.sql.run("CREATE TABLE IF NOT EXISTS slots (pairId TEXT PRIMARY KEY, state TEXT NOT NULL, phonePub TEXT, sealed TEXT, expiresAt INTEGER NOT NULL)");
    ensureRatesTable(this.sql);
  }

  rate(key, limit, windowSec) {
    return checkRate(this.sql, String(key), limit, windowSec, this.now());
  }

  startPairing() {
    const now = this.now();
    this.sql.run("DELETE FROM slots WHERE expiresAt < ?", now);
    this.sql.run("DELETE FROM rates WHERE windowStart + ? < ?", LONGEST_RATE_WINDOW, now);
    const pairId = randomId(16);
    const expiresAt = now + this.limits.pairTtlSec;
    this.sql.run("INSERT INTO slots (pairId, state, expiresAt) VALUES (?, 'waiting', ?)", pairId, expiresAt);
    return { ok: true, pairId, expiresAt };
  }

  joinPairing(pairId, phonePub) {
    const slot = this.live(pairId);
    if (!slot.ok) return slot;
    if (!isB64url(phonePub, PHONE_PUB_CHARS, PHONE_PUB_CHARS)) return fail(400, "bad_request");
    if (slot.row.state === "cancelled") return fail(409, "wrong_state");
    if (slot.row.state !== "waiting") return fail(409, "slot_taken");
    this.sql.run("UPDATE slots SET state = 'joined', phonePub = ? WHERE pairId = ?", phonePub, pairId);
    return { ok: true };
  }

  replyPairing(pairId, sealed) {
    const slot = this.live(pairId);
    if (!slot.ok) return slot;
    if (typeof sealed === "string" && sealed.length > SEALED_MAX) return fail(413, "too_large");
    if (!isB64url(sealed, 1, SEALED_MAX)) return fail(400, "bad_request");
    if (slot.row.state !== "joined") return fail(409, "wrong_state");
    this.sql.run("UPDATE slots SET state = 'replied', sealed = ? WHERE pairId = ?", sealed, pairId);
    return { ok: true };
  }

  /** Reads the slot. A reply is handed out once, then the slot is deleted. */
  getPairing(pairId) {
    const slot = this.live(pairId);
    if (!slot.ok) return slot;
    const { state, phonePub, sealed } = slot.row;
    if (state === "joined") return { ok: true, state, phonePub };
    if (state === "replied") {
      this.sql.run("DELETE FROM slots WHERE pairId = ?", pairId);
      return { ok: true, state, sealed };
    }
    return { ok: true, state };
  }

  cancelPairing(pairId) {
    const slot = this.live(pairId);
    if (!slot.ok) return slot;
    this.sql.run("UPDATE slots SET state = 'cancelled', phonePub = NULL, sealed = NULL WHERE pairId = ?", pairId);
    return { ok: true };
  }

  /** The slot if it exists and has not expired; an expired one is deleted and reported gone. */
  live(pairId) {
    if (!isB64url(pairId, PAIR_ID_CHARS, PAIR_ID_CHARS)) return fail(404, "not_found");
    const row = this.sql.all("SELECT pairId, state, phonePub, sealed, expiresAt FROM slots WHERE pairId = ?", pairId)[0];
    if (!row) return fail(404, "not_found");
    if (this.now() > row.expiresAt) {
      this.sql.run("DELETE FROM slots WHERE pairId = ?", pairId);
      return fail(410, "gone");
    }
    return { ok: true, row };
  }
}
