import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { MirrorStore } from "../src/store.js";
import { nodeSqlite } from "../src/sql.js";
import { LIMITS } from "../src/limits.js";
import { sha256Hex } from "../src/auth.js";
import { makeClock } from "./support/clock.js";

async function makeStore(limits = {}) {
  const clock = makeClock();
  const store = new MirrorStore(nodeSqlite(new DatabaseSync(":memory:")), { now: clock.now, limits });
  store.init();
  const owner = { deviceId: "ownerDev", token: "ownerTok" };
  const created = store.create({ deviceId: owner.deviceId, ownerTokenHash: await sha256Hex(owner.token) });
  assert.equal(created.ok, true);
  return { store, clock, ownerBearer: `Bearer ${owner.deviceId}.${owner.token}` };
}

async function addBrowser(store, ownerBearer, n = 1) {
  const deviceId = `browser${n}`;
  const token = `token${n}`;
  const r = await store.addDevice(ownerBearer, { deviceId, tokenHash: await sha256Hex(token) });
  assert.equal(r.ok, true, JSON.stringify(r));
  return `Bearer ${deviceId}.${token}`;
}

const item = (n, sealed = "AAAA") => ({ id: `item${String(n).padStart(20, "0")}`, sealed });

test("create makes one owner device, a second create is refused", async () => {
  const { store } = await makeStore();
  const again = store.create({ deviceId: "x", ownerTokenHash: await sha256Hex("t") });
  assert.deepEqual(again, { ok: false, status: 409, error: "already_created" });
});

test("authenticate: right bearer works, wrong token / unknown / bad header are 401, wrong role is 403", async () => {
  const { store, ownerBearer } = await makeStore();
  const browser = await addBrowser(store, ownerBearer);
  const ok = await store.authenticate(ownerBearer);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.device, { deviceId: "ownerDev", role: "owner" });
  for (const bad of ["Bearer ownerDev.wrong", "Bearer nobody.ownerTok", "garbage", null]) {
    assert.deepEqual(await store.authenticate(bad), { ok: false, status: 401, error: "unauthorized" }, String(bad));
  }
  assert.deepEqual(await store.authenticate(browser, "owner"), { ok: false, status: 403, error: "forbidden" });
  assert.equal((await store.authenticate(browser, "browser")).ok, true);
});

test("addDevice: owner only, cap of 8 browsers, duplicates and bad hashes refused", async () => {
  const { store, ownerBearer } = await makeStore();
  const browser = await addBrowser(store, ownerBearer, 1);
  const byBrowser = await store.addDevice(browser, { deviceId: "z", tokenHash: await sha256Hex("z") });
  assert.equal(byBrowser.status, 403);
  assert.deepEqual(await store.addDevice(ownerBearer, { deviceId: "browser1", tokenHash: await sha256Hex("q") }), { ok: false, status: 409, error: "device_exists" });
  assert.equal((await store.addDevice(ownerBearer, { deviceId: "bad", tokenHash: "NOTHEX" })).status, 400);
  for (let n = 2; n <= 8; n++) await addBrowser(store, ownerBearer, n);
  assert.deepEqual(await store.addDevice(ownerBearer, { deviceId: "ninth", tokenHash: await sha256Hex("9") }), { ok: false, status: 409, error: "too_many_devices" });
});

test("removeDevice: the removed browser is locked out at once, the owner cannot be removed", async () => {
  const { store, ownerBearer } = await makeStore();
  const browser = await addBrowser(store, ownerBearer);
  assert.equal((await store.authenticate(browser)).ok, true);
  assert.equal((await store.removeDevice(ownerBearer, "browser1")).ok, true);
  assert.equal((await store.authenticate(browser)).status, 401);
  assert.deepEqual(await store.removeDevice(ownerBearer, "ownerDev"), { ok: false, status: 400, error: "owner_device" });
  assert.equal((await store.removeDevice(ownerBearer, "ghost")).status, 404);
});

test("putItems: increasing seq, upsert replaces with a new seq, tombstones are listed", async () => {
  const { store, ownerBearer } = await makeStore();
  const r = await store.putItems(ownerBearer, [item(1), item(2), item(3)]);
  assert.deepEqual(r, { ok: true, seq: 3 });
  const r2 = await store.putItems(ownerBearer, [item(1, "BBBB")]);
  assert.equal(r2.seq, 4);
  const listed = await store.listItems(ownerBearer, 0, 100);
  assert.deepEqual(listed.items.map((i) => [i.id, i.seq, i.sealed]), [
    [item(2).id, 2, "AAAA"],
    [item(3).id, 3, "AAAA"],
    [item(1).id, 4, "BBBB"],
  ]);
  await store.putItems(ownerBearer, [{ id: item(2).id, sealed: "", deleted: true }]);
  const after = await store.listItems(ownerBearer, 4, 100);
  assert.deepEqual(after.items, [{ id: item(2).id, seq: 5, sealed: "", deleted: true }]);
});

test("putItems validates everything first: nothing is written on any bad item", async () => {
  const { store, ownerBearer } = await makeStore();
  const before = (await store.state(ownerBearer)).seq;
  assert.deepEqual(await store.putItems(ownerBearer, Array.from({ length: 201 }, (_, i) => item(i))), { ok: false, status: 400, error: "too_many_items" });
  assert.equal((await store.putItems(ownerBearer, [item(1), { id: "bad id!", sealed: "AAAA" }])).status, 400);
  assert.equal((await store.putItems(ownerBearer, [item(1), { id: item(2).id, sealed: "no+padding=" }])).status, 400);
  assert.equal((await store.putItems(ownerBearer, [item(1), item(1)])).status, 400);
  assert.equal((await store.putItems(ownerBearer, [])).status, 400);
  assert.equal((await store.putItems(ownerBearer, [item(1), { id: item(2).id, sealed: "A".repeat(LIMITS.sealedChars + 1) }])).status, 413);
  assert.equal((await store.state(ownerBearer)).seq, before);
  assert.equal((await store.listItems(ownerBearer, 0, 10)).items.length, 0);
  assert.equal((await store.putItems(ownerBearer, [item(1, "A".repeat(LIMITS.sealedChars))])).ok, true);
});

test("putItems: a browser token is refused, and the mirror has a total cap", async () => {
  const { store, ownerBearer } = await makeStore({ itemsTotal: 5 });
  const browser = await addBrowser(store, ownerBearer);
  assert.equal((await store.putItems(browser, [item(1)])).status, 403);
  assert.equal((await store.putItems(ownerBearer, [item(1), item(2), item(3), item(4), item(5)])).ok, true);
  assert.deepEqual(await store.putItems(ownerBearer, [item(6)]), { ok: false, status: 409, error: "mirror_full" });
  assert.equal((await store.putItems(ownerBearer, [item(5, "CCCC")])).ok, true, "replacing an existing item is not growth");
});

test("listItems: since, paging with more, clamped limit, both roles may read", async () => {
  const { store, ownerBearer } = await makeStore();
  const browser = await addBrowser(store, ownerBearer);
  await store.putItems(ownerBearer, [1, 2, 3, 4, 5].map((n) => item(n)));
  const all = await store.listItems(browser, 0, 100);
  assert.deepEqual(all.items.map((i) => i.seq), [1, 2, 3, 4, 5]);
  assert.equal(all.more, false);
  assert.equal(all.seq, 5);
  const p1 = await store.listItems(browser, 0, 2);
  assert.deepEqual([p1.items.length, p1.more], [2, true]);
  const p2 = await store.listItems(browser, p1.items.at(-1).seq, 2);
  const p3 = await store.listItems(browser, p2.items.at(-1).seq, 2);
  assert.deepEqual([p2.items.map((i) => i.seq), p2.more, p3.items.map((i) => i.seq), p3.more], [[3, 4], true, [5], false]);
  assert.equal((await store.listItems(browser, 3, 100)).items.length, 2);
  assert.equal((await store.listItems(browser, 0, 0)).items.length, 1, "limit clamps up to 1");
  assert.equal((await store.listItems(browser, 0, 9999)).items.length, 5, "limit clamps down to 200");
  assert.equal((await store.listItems(browser, -1, 10)).status, 400);
  assert.equal((await store.listItems(browser, 1.5, 10)).status, 400);
});

test("listItems stops at the soft byte cap but is never empty", async () => {
  const { store, ownerBearer } = await makeStore();
  const big = "A".repeat(LIMITS.sealedChars);
  await store.putItems(ownerBearer, [item(1, big), item(2, big), item(3, big)]);
  await store.putItems(ownerBearer, [item(4, big)]);
  const page1 = await store.listItems(ownerBearer, 0, 200);
  assert.deepEqual([page1.items.length, page1.more], [3, true]);
  const tiny = await makeStore({ listSealedSoft: 10 });
  await tiny.store.putItems(tiny.ownerBearer, [item(1, "AAAAAAAAAAAAAAAAAAAA"), item(2, "AAAAAAAAAAAAAAAAAAAA")]);
  const one = await tiny.store.listItems(tiny.ownerBearer, 0, 200);
  assert.deepEqual([one.items.length, one.more], [1, true]);
});

test("lastSeen updates at most once per minute", async () => {
  const { store, clock, ownerBearer } = await makeStore();
  const seen = async () => (await store.listDevices(ownerBearer)).devices.find((d) => d.deviceId === "ownerDev").lastSeen;
  const t0 = clock.now();
  assert.equal(await seen(), t0);
  clock.advance(30);
  assert.equal(await seen(), t0);
  clock.advance(31);
  await store.state(ownerBearer);
  assert.equal(await seen(), t0 + 61);
});

test("per-device rate limit answers 429 with retryAfter and resets with the window", async () => {
  const { store, clock, ownerBearer } = await makeStore({ rates: { ...LIMITS.rates, itemsPut: [2, 60] } });
  assert.equal((await store.putItems(ownerBearer, [item(1)])).ok, true);
  assert.equal((await store.putItems(ownerBearer, [item(2)])).ok, true);
  const third = await store.putItems(ownerBearer, [item(3)]);
  assert.equal(third.status, 429);
  assert.equal(third.error, "rate_limited");
  assert.ok(third.retryAfter >= 1 && third.retryAfter <= 60);
  clock.advance(60);
  assert.equal((await store.putItems(ownerBearer, [item(3)])).ok, true);
});
