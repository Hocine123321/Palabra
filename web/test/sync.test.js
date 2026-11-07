import test from "node:test";
import assert from "node:assert/strict";
import { createSync } from "../src/sync.js";
import { createCache, memoryStore } from "../src/cache.js";

const SECRET = "ab".repeat(32);
const fresh = (n) => ({ snapshot: { words: [{ id: String(n) }] }, takenAt: `2026-11-07T10:0${n}:00Z` });

function timers() {
  const q = []; let id = 0;
  return { setTimer: (fn, ms) => { q.push({ id: ++id, fn, ms }); return id; }, clearTimer: (i) => { const k = q.findIndex((t) => t.id === i); if (k >= 0) q.splice(k, 1); },
    pending: () => q.length, next: () => q[0]?.ms, fire: async () => { const t = q.shift(); await t.fn(); await tick(); } };
}
const tick = () => new Promise((r) => setImmediate(r));

function harness({ replies = [], cache = createCache(memoryStore()) } = {}) {
  const t = timers(); const seen = []; let opens = 0, closed = 0;
  const openLink = async () => {
    opens++;
    const next = replies.shift();
    if (next instanceof Error || next?.fail) throw next;
    return { request: async () => { if (next?.requestFails) throw next.requestFails; return next; }, close: () => { closed++; } };
  };
  const sync = createSync({ cache, openLink, onChange: (v) => seen.push(v), ...t });
  return { sync, cache, t, seen, opens: () => opens, closed: () => closed, last: () => seen[seen.length - 1] };
}

test("fresh data from the phone is shown and saved", async () => {
  const h = harness({ replies: [fresh(1)] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "linked");
  assert.equal(h.last().snapshot.words[0].id, "1");
  assert.equal((await h.cache.loadSnapshot()).takenAt, "2026-11-07T10:01:00Z");
});

test("offline start: the saved copy is on screen at once, state says the phone is away, and it keeps retrying", async () => {
  const cache = createCache(memoryStore());
  await cache.saveSnapshot({ words: [{ id: "saved" }] }, "2026-11-06T09:00:00Z");
  const h = harness({ cache, replies: [new Error("no relay")] });
  assert.equal(await h.sync.showCached(), true);
  assert.equal(h.last().snapshot.words[0].id, "saved");
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "away");
  assert.equal(h.last().snapshot.words[0].id, "saved");         // still there
  assert.equal(h.last().takenAt, "2026-11-06T09:00:00Z");       // and honest about its age
  assert.equal(h.t.pending(), 1);
});

test("offline with nothing saved says so", async () => {
  const h = harness({ replies: [new Error("no relay")] });
  assert.equal(await h.sync.showCached(), false);
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "empty"); assert.equal(h.last().snapshot, null);
});

test("when the phone comes back the saved copy is replaced by the fresh one", async () => {
  const cache = createCache(memoryStore());
  await cache.saveSnapshot({ words: [{ id: "old" }] }, "2026-11-06T09:00:00Z");
  const h = harness({ cache, replies: [new Error("down"), fresh(2)] });
  await h.sync.showCached();
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "away");
  await h.t.fire();
  assert.equal(h.last().state, "linked");
  assert.deepEqual(h.last().snapshot.words.map((w) => w.id), ["2"]);
  assert.deepEqual((await cache.loadSnapshot()).snapshot.words.map((w) => w.id), ["2"]);
});

test("retries back off, never overlap, and the delay resets after a success", async () => {
  const h = harness({ replies: [new Error("1"), new Error("2"), new Error("3"), new Error("4"), new Error("5"), fresh(1)] });
  await h.sync.start(SECRET, "wss://r");
  const waits = [h.t.next()];
  for (let i = 0; i < 4; i++) { await h.t.fire(); waits.push(h.t.next()); }
  assert.deepEqual(waits.slice(0, 5), [2000, 5000, 15000, 30000, 30000]);   // capped at the last step
  assert.equal(h.t.pending(), 1);                                           // one timer at a time
  await h.t.fire();
  assert.equal(h.last().state, "linked");
  assert.equal(h.t.pending(), 0);
});

test("a failed connection attempt closes the half-open link", async () => {
  const h = harness({ replies: [{ requestFails: Object.assign(new Error("timeout"), { kind: "no-answer" }) }] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.closed(), 1);
});

test("a damaged snapshot reply is not saved and does not wipe the saved copy", async () => {
  const cache = createCache(memoryStore());
  await cache.saveSnapshot({ words: [{ id: "keep" }] }, "2026-11-06T09:00:00Z");
  const h = harness({ cache, replies: [{ nonsense: true }] });
  await h.sync.showCached();
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "away");
  assert.equal((await cache.loadSnapshot()).snapshot.words[0].id, "keep");
});

test("a browser that cannot save still shows the fresh data", async () => {
  const broken = createCache({ get: async () => { throw new Error("x"); }, set: async () => { throw new Error("quota"); }, delete: async () => {}, keys: async () => [] });
  const h = harness({ cache: broken, replies: [fresh(3)] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "linked"); assert.equal(h.last().snapshot.words[0].id, "3");
});

test("a revoked pairing is an error that needs the person, and it stops retrying", async () => {
  const h = harness({ replies: [{ requestFails: Object.assign(new Error("Pair again"), { kind: "revoked" }) }] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().state, "error");
  assert.equal(h.t.pending(), 0, "must not keep retrying a pairing the phone has revoked");
});

test("stop() cancels the retry and closes the link; nothing runs afterwards", async () => {
  const h = harness({ replies: [new Error("down"), fresh(1)] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.t.pending(), 1);
  h.sync.stop();
  assert.equal(h.t.pending(), 0);
  assert.equal(h.opens(), 1);
});

test("link lost after being linked falls back to the saved copy and reconnects", async () => {
  const h = harness({ replies: [fresh(1), fresh(2)] });
  await h.sync.start(SECRET, "wss://r");
  h.sync.linkLost(SECRET, "wss://r");
  assert.equal(h.last().state, "away"); assert.equal(h.last().snapshot.words[0].id, "1");
  await h.t.fire();
  assert.equal(h.last().state, "linked"); assert.equal(h.last().snapshot.words[0].id, "2");
});

test("refresh updates the data when the phone answers and keeps the old data when it does not", async () => {
  let answer = fresh(1);
  const link = { request: async () => { if (answer instanceof Error) throw answer; return answer; }, close() {} };
  const cache = createCache(memoryStore()); const seen = [];
  const sync = createSync({ cache, openLink: async () => link, onChange: (v) => seen.push(v), ...timers() });
  assert.equal(await sync.refresh(), false);                      // not linked yet
  await sync.start(SECRET, "wss://r");
  answer = fresh(2);
  assert.equal(await sync.refresh(), true);
  assert.equal(seen.at(-1).snapshot.words[0].id, "2");
  answer = new Error("silent");
  assert.equal(await sync.refresh(), false);
  assert.equal(seen.at(-1).state, "away");
  assert.equal(seen.at(-1).snapshot.words[0].id, "2");            // still the last good copy
  assert.equal((await cache.loadSnapshot()).snapshot.words[0].id, "2");
});

test("consecutive failures are counted so the page can suggest re-pairing, and a success resets the count", async () => {
  const h = harness({ replies: [new Error("1"), new Error("2"), new Error("3"), fresh(1), new Error("x")] });
  await h.sync.start(SECRET, "wss://r");
  assert.equal(h.last().failures, 1);
  await h.t.fire(); await h.t.fire();
  assert.equal(h.last().failures, 3);
  await h.t.fire();
  assert.equal(h.last().state, "linked"); assert.equal(h.last().failures, 0);
});
