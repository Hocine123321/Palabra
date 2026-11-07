import test from "node:test";
import assert from "node:assert/strict";
import { sendOutboxItem, callAiLive } from "../src/writes.js";
import { createOutbox, LiveOnlyError } from "../src/outbox.js";
import { createRpc, LinkRpcError } from "../src/link-rpc.js";
import { memoryStore } from "../src/cache.js";
import { AR, makeT } from "../src/ui/strings.js";
import { reasonText } from "../src/link-rpc.js";

test("a waiting action goes to the phone as a write carrying its id, capability, args and base", async () => {
  const sent = [];
  const link = { request: async (type, payload) => { sent.push({ type, payload }); return { ok: true }; } };
  await sendOutboxItem(() => link)({ id: "a1", capability: "words.place", args: { words: [] }, base: "v1" });
  assert.deepEqual(sent, [{ type: "write", payload: { id: "a1", capability: "words.place", args: { words: [] }, base: "v1" } }]);
});

test("with no link the outbox keeps the action (the phone is simply away)", async () => {
  const ob = createOutbox({ store: memoryStore(), send: sendOutboxItem(() => null), newId: () => "i1" });
  await ob.enqueue("words.add", { words: ["a"] });
  assert.deepEqual(await ob.flush(), { sent: 0, rejected: 0 });
  assert.equal(ob.snapshot.waiting, 1);
});

test("AI calls need a live link and are never stored", async () => {
  await assert.rejects(callAiLive(() => null, { prompt: "x" }), LiveOnlyError);
  const seen = [];
  const out = await callAiLive(() => ({ request: async (t, p) => { seen.push(t); return { text: "hola" }; } }), { prompt: "x" });
  assert.deepEqual(seen, ["ai"]); assert.equal(out.text, "hola");
});

test("a phone refusal travels through the real RPC layer into the review list with a readable reason", async () => {
  let rpc; const frames = [];
  rpc = createRpc({ send: (m) => { frames.push(m); queueMicrotask(() => rpc.receive({ id: m.id, type: "reject", version: 1, payload: { reason: "conflict" } })); } });
  const link = { request: (t, p) => rpc.request(t, p) };
  const ob = createOutbox({ store: memoryStore(), send: sendOutboxItem(() => link), newId: () => "i1" });
  await ob.enqueue("words.place", { words: [{ key: "a", category: "x" }] }, "v1");
  assert.deepEqual(await ob.flush(), { sent: 0, rejected: 1 });
  assert.equal(frames[0].type, "write");
});

test("the new reasons have Arabic and match their English text", () => {
  for (const reason of ["conflict", "not-found", "live-only", "not-queueable"]) {
    const english = reasonText(reason);
    assert.notEqual(english, reasonText("zzz"), reason);
    assert.ok(AR[english], `no Arabic for ${reason}`);
  }
});

import { placementBase } from "../src/writes.js";
import { placementToken } from "../src/ui/model.js";

test("the base for a placement change is a token per touched word, taken from what the page saw", () => {
  const words = [{ id: "1", key: "hola", category: "Food", tags: ["b", "a"] }, { id: "2", key: "adios", category: null, tags: [] }, { id: "3", key: "other", category: "Z", tags: [] }];
  assert.deepEqual(placementBase(words, ["hola", "2"], placementToken), { hola: "Food|a,b", "2": "|" });
  assert.deepEqual(placementBase(words, ["unknown"], placementToken), {}, "a word the page never saw gets no base");
});

import { parseWords } from "../src/writes.js";

test("typed words are split, trimmed, de-duplicated and kept within the phone's limits", () => {
  assert.deepEqual(parseWords("hola, adiós,  buenas   noches"), ["hola", "adiós", "buenas noches"]);
  assert.deepEqual(parseWords("Hola, hola, HOLA"), ["Hola"]);
  assert.deepEqual(parseWords("a\nb;c،d"), ["a", "b", "c", "d"]);
  assert.deepEqual(parseWords(",, ,"), []);
  assert.deepEqual(parseWords(null), []);
  assert.deepEqual(parseWords("x".repeat(81) + ", ok"), ["ok"], "a word over 80 characters is dropped");
  assert.equal(parseWords(Array.from({ length: 30 }, (_, i) => `w${i}`).join(",")).length, 20);
});
