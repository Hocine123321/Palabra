import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { GateStore } from "../src/gate.js";
import { nodeSqlite } from "../src/sql.js";
import { LIMITS } from "../src/limits.js";
import { makeClock } from "./support/clock.js";

function makeGate() {
  const clock = makeClock();
  const db = new DatabaseSync(":memory:");
  const gate = new GateStore(nodeSqlite(db), { now: clock.now });
  gate.init();
  return { gate, clock, db };
}

const PUB = "B".repeat(87);
const SEALED = "S".repeat(200);
const rows = (db) => db.prepare("SELECT COUNT(*) AS n FROM slots").get().n;

test("happy path: start, join, reply, and the reply is read once", () => {
  const { gate } = makeGate();
  const { pairId, expiresAt } = gate.startPairing();
  assert.equal(pairId.length, 22);
  assert.equal(expiresAt, 1_000_000 + LIMITS.pairTtlSec);
  assert.deepEqual(gate.getPairing(pairId), { ok: true, state: "waiting" });
  assert.deepEqual(gate.joinPairing(pairId, PUB), { ok: true });
  assert.deepEqual(gate.getPairing(pairId), { ok: true, state: "joined", phonePub: PUB });
  assert.deepEqual(gate.replyPairing(pairId, SEALED), { ok: true });
  assert.deepEqual(gate.getPairing(pairId), { ok: true, state: "replied", sealed: SEALED });
  assert.deepEqual(gate.getPairing(pairId), { ok: false, status: 404, error: "not_found" });
});

test("a slot takes one join; reply needs a join and happens once", () => {
  const { gate } = makeGate();
  const { pairId } = gate.startPairing();
  assert.deepEqual(gate.replyPairing(pairId, SEALED), { ok: false, status: 409, error: "wrong_state" });
  gate.joinPairing(pairId, PUB);
  assert.deepEqual(gate.joinPairing(pairId, PUB), { ok: false, status: 409, error: "slot_taken" });
  gate.replyPairing(pairId, SEALED);
  assert.deepEqual(gate.replyPairing(pairId, SEALED), { ok: false, status: 409, error: "wrong_state" });
  assert.equal(gate.joinPairing(pairId, PUB).error, "slot_taken", "a join after a reply is refused");
});

test("input checks: phonePub must be 87 base64url characters, sealed at most 4096", () => {
  const { gate } = makeGate();
  const { pairId } = gate.startPairing();
  for (const bad of ["B".repeat(86), "B".repeat(88), "B".repeat(86) + "=", "", 5, null]) {
    assert.equal(gate.joinPairing(pairId, bad).status, 400, String(bad));
  }
  gate.joinPairing(pairId, PUB);
  assert.equal(gate.replyPairing(pairId, "S".repeat(4097)).status, 413);
  assert.equal(gate.replyPairing(pairId, "").status, 400);
  assert.equal(gate.replyPairing(pairId, "no=pad").status, 400);
  assert.equal(gate.replyPairing(pairId, "S".repeat(4096)).ok, true);
});

test("a slot is live at expiresAt and gone one second later", () => {
  for (const op of ["get", "join", "reply"]) {
    const { gate, clock, db } = makeGate();
    const { pairId, expiresAt } = gate.startPairing();
    if (op === "reply") gate.joinPairing(pairId, PUB);
    clock.advance(expiresAt - clock.now());
    const call = () => (op === "get" ? gate.getPairing(pairId) : op === "join" ? gate.joinPairing(pairId, PUB) : gate.replyPairing(pairId, SEALED));
    if (op === "get") assert.equal(call().ok, true, "live at the boundary");
    clock.advance(1);
    assert.deepEqual(call(), { ok: false, status: 410, error: "gone" }, op);
    assert.equal(rows(db), 0, "the expired slot is deleted");
  }
});

test("cancel keeps a cancelled state until expiry and blocks join and reply", () => {
  const { gate } = makeGate();
  const a = gate.startPairing().pairId;
  assert.deepEqual(gate.cancelPairing(a), { ok: true });
  assert.deepEqual(gate.getPairing(a), { ok: true, state: "cancelled" });
  assert.equal(gate.joinPairing(a, PUB).error, "wrong_state");
  const b = gate.startPairing().pairId;
  gate.joinPairing(b, PUB);
  gate.cancelPairing(b);
  assert.equal(gate.replyPairing(b, SEALED).error, "wrong_state");
  assert.equal(gate.cancelPairing("x".repeat(22)).status, 404);
});

test("unknown or malformed pair ids are 404", () => {
  const { gate } = makeGate();
  for (const id of ["short", "x".repeat(22), "a/b", "x".repeat(23), "", null, undefined]) {
    assert.equal(gate.getPairing(id).status, 404, String(id));
    assert.equal(gate.joinPairing(id, PUB).status, 404, String(id));
    assert.equal(gate.replyPairing(id, SEALED).status, 404, String(id));
  }
});

test("startPairing sweeps expired slots; ids are distinct", () => {
  const { gate, clock, db } = makeGate();
  gate.startPairing();
  gate.startPairing();
  assert.equal(rows(db), 2);
  clock.advance(LIMITS.pairTtlSec + 1);
  gate.startPairing();
  assert.equal(rows(db), 1);
  const ids = new Set();
  for (let i = 0; i < 1000; i++) ids.add(gate.startPairing().pairId);
  assert.equal(ids.size, 1000);
});

test("rate: limit per key, independent keys, window resets", () => {
  const { gate, clock } = makeGate();
  for (let i = 0; i < 3; i++) assert.equal(gate.rate("ip1", 3, 600).ok, true);
  const fourth = gate.rate("ip1", 3, 600);
  assert.equal(fourth.status, 429);
  assert.ok(fourth.retryAfter >= 1 && fourth.retryAfter <= 600);
  assert.equal(gate.rate("ip2", 3, 600).ok, true);
  clock.advance(600);
  assert.equal(gate.rate("ip1", 3, 600).ok, true);
});

test("stale rate counters are pruned when a new window opens", () => {
  const { gate, clock, db } = makeGate();
  gate.rate("old", 5, 60);
  clock.advance(7200);
  gate.rate("new", 5, 60);
  const keys = db.prepare("SELECT key FROM rates").all().map((r) => r.key);
  assert.deepEqual(keys, ["new"]);
});
