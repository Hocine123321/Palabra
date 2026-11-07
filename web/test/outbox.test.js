import test from "node:test";
import assert from "node:assert/strict";
import { createOutbox, QUEUEABLE, LIVE_ONLY, MAX_QUEUED, LiveOnlyError } from "../src/outbox.js";
import { memoryStore } from "../src/cache.js";

const away = () => Object.assign(new Error("silent"), { kind: "no-answer" });
const refuse = (kind, message = "") => Object.assign(new Error(message), { kind });

function make({ send, store = memoryStore() } = {}) {
  let n = 0; const seen = [];
  const ob = createOutbox({ store, send: send ?? (async () => ({ ok: true })), onChange: (v) => seen.push(v), newId: () => `id${++n}` });
  return { ob, store, seen, last: () => seen.at(-1) };
}

test("actions go out oldest first, one at a time, and are removed once the phone confirms", async () => {
  const order = [];
  const { ob, last } = make({ send: async (item) => { order.push(item.id); return {}; } });
  await ob.enqueue("words.add", { words: ["a"] });
  await ob.enqueue("words.add", { words: ["b"] });
  await ob.enqueue("review.flag", { words: [{ key: "a" }] });
  assert.equal(last().waiting, 3);
  assert.deepEqual(await ob.flush(), { sent: 3, rejected: 0 });
  assert.deepEqual(order, ["id1", "id2", "id3"]);
  assert.equal(last().waiting, 0);
});

test("when the phone is away nothing is lost, nothing is skipped, and order is kept", async () => {
  let up = false; const order = [];
  const { ob, last } = make({ send: async (item) => { if (!up) throw away(); order.push(item.id); return {}; } });
  await ob.enqueue("words.add", { words: ["a"] }); await ob.enqueue("words.add", { words: ["b"] });
  assert.deepEqual(await ob.flush(), { sent: 0, rejected: 0 });
  assert.equal(last().waiting, 2);
  up = true;
  await ob.flush();
  assert.deepEqual(order, ["id1", "id2"]);
});

test("a refusal moves that action to review with the reason, and the ones after it still go out", async () => {
  const { ob, last } = make({ send: async (item) => { if (item.id === "id2") throw refuse("conflict", "changed on the phone"); return {}; } });
  await ob.enqueue("words.place", { words: [{ key: "a", category: "x" }] }, "v1");
  await ob.enqueue("words.place", { words: [{ key: "b", category: "y" }] }, "v1");
  await ob.enqueue("words.add", { words: ["c"] });
  assert.deepEqual(await ob.flush(), { sent: 2, rejected: 1 });
  assert.equal(last().waiting, 0);
  assert.equal(last().review.length, 1);
  assert.equal(last().review[0].id, "id2"); assert.equal(last().review[0].reason, "conflict"); assert.equal(last().review[0].message, "changed on the phone");
});

test("AI calls are never queued: they throw, and nothing is stored", async () => {
  const { ob, last } = make();
  await assert.rejects(ob.enqueue("ai.generate", { prompt: "x" }), LiveOnlyError);
  assert.equal(ob.snapshot.waiting, 0);
  assert.equal(last(), undefined, "nothing was stored or published");
  assert.ok(LIVE_ONLY.has("ai.generate")); assert.ok(!QUEUEABLE.has("ai.generate"));
});

test("anything not on the queueable list is refused, including deletes and storage writes", async () => {
  const { ob } = make();
  for (const name of ["words.delete", "storage.set", "storage.remove", "settings.apiKey", "unknown"]) {
    await assert.rejects(ob.enqueue(name, {}), (e) => e.kind === "not-queueable", name);
  }
});

test("the queue is capped so a runaway page cannot fill the browser", async () => {
  const { ob } = make();
  for (let i = 0; i < MAX_QUEUED; i++) await ob.enqueue("words.add", { words: [String(i)] });
  await assert.rejects(ob.enqueue("words.add", { words: ["one too many"] }), (e) => e.kind === "full");
});

test("waiting actions survive a reload, in order", async () => {
  const store = memoryStore();
  const a = make({ store, send: async () => { throw away(); } });
  await a.ob.enqueue("words.add", { words: ["a"] }); await a.ob.enqueue("words.add", { words: ["b"] });
  const sent = []; const b = make({ store, send: async (i) => { sent.push(i.args.words[0]); return {}; } });
  await b.ob.load();
  assert.equal(b.last().waiting, 2);
  await b.ob.flush();
  assert.deepEqual(sent, ["a", "b"]);
});

test("a damaged or foreign stored outbox is ignored, not trusted", async () => {
  const store = memoryStore();
  await store.set("outbox", { schema: 99, queue: [{ id: "evil", capability: "storage.set" }], review: [] });
  const { ob, last } = make({ store }); await ob.load();
  assert.equal(last().waiting, 0);
  await store.set("outbox", "garbage"); await ob.load();
  assert.equal(last().waiting, 0);
});

test("a stored outbox cannot smuggle in a live-only or unknown action: flush only sends what was queueable when queued", async () => {
  // load() restores what was saved; the phone enforces the list again, so even a tampered store cannot make it run ai.generate.
  // Here we check the page side: such an item is dropped to review instead of being sent.
  const store = memoryStore();
  await store.set("outbox", { schema: 1, queue: [{ id: "x", capability: "ai.generate", args: {}, base: null, at: "t", tries: 0 }], review: [] });
  let sentAny = false;
  const { ob, last } = make({ store, send: async () => { sentAny = true; return {}; } }); await ob.load();
  await ob.flush();
  assert.equal(sentAny, false);
  assert.equal(last().review[0].reason, "not-queueable");
});

test("retry puts a reviewed action back at the end without its old version; drop removes it", async () => {
  const { ob, last } = make({ send: async () => { throw refuse("conflict"); } });
  await ob.enqueue("words.place", { words: [] }, "v1"); await ob.flush();
  assert.equal(last().review.length, 1);
  assert.equal(await ob.retry("id1"), true);
  assert.equal(last().waiting, 1); assert.equal(last().review.length, 0); assert.equal(last().queue[0].base, null);
  await ob.flush();
  assert.equal(await ob.drop("id1"), true); assert.equal(last().review.length, 0);
  assert.equal(await ob.retry("nope"), false); assert.equal(await ob.drop("nope"), false);
});

test("two flushes at once never send the same action twice", async () => {
  let calls = 0; let release;
  const gate = new Promise((r) => { release = r; });
  const { ob } = make({ send: async () => { calls++; await gate; return {}; } });
  await ob.enqueue("words.add", { words: ["a"] });
  const first = ob.flush(); const second = ob.flush();
  release(); await Promise.all([first, second]);
  assert.equal(calls, 1);
});

test("a browser that cannot save does not stop actions from being sent in this visit", async () => {
  const broken = { get: async () => { throw new Error("x"); }, set: async () => { throw new Error("quota"); }, delete: async () => {}, keys: async () => [] };
  let sent = 0;
  const { ob } = make({ store: broken, send: async () => { sent++; return {}; } });
  await ob.enqueue("words.add", { words: ["a"] });
  await ob.flush();
  assert.equal(sent, 1);
});

test("clear removes the stored record entirely rather than saving an empty one", async () => {
  const store = memoryStore();
  const { ob } = make({ store });
  await ob.enqueue("words.add", { words: ["a"] });
  assert.deepEqual(await store.keys(), ["outbox"]);
  await ob.clear();
  assert.deepEqual(await store.keys(), []);
  assert.equal(ob.snapshot.waiting, 0);
});
