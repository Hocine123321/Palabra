import test from "node:test";
import assert from "node:assert/strict";
import { createRpc, LinkRpcError } from "../src/link-rpc.js";

const b64 = (bytes) => Buffer.from(bytes).toString("base64");
const fakeTimers = () => {
  const timers = new Map(); let n = 0;
  return { setTimer: (fn) => { timers.set(++n, fn); return n; }, clearTimer: (id) => timers.delete(id), fire: () => { for (const [id, fn] of [...timers]) { timers.delete(id); fn(); } } };
};

test("a request resolves with the matching reply payload", async () => {
  const sent = [];
  const rpc = createRpc({ send: (m) => sent.push(m) });
  const p = rpc.request("read", { capability: "library.words" });
  assert.equal(sent[0].type, "read"); assert.equal(sent[0].version, 1);
  rpc.receive({ id: "other", type: "ack", payload: { no: true } });          // someone else's reply is ignored
  rpc.receive({ id: sent[0].id, type: "ack", version: 1, payload: { result: [1] } });
  assert.deepEqual(await p, { result: [1] });
  assert.equal(rpc.pending(), 0);
});

test("a reject becomes a LinkRpcError carrying the reason code", async () => {
  const sent = []; const rpc = createRpc({ send: (m) => sent.push(m) });
  const p = rpc.request("read", {});
  rpc.receive({ id: sent[0].id, type: "reject", payload: { reason: "forbidden" } });
  await assert.rejects(p, (e) => e instanceof LinkRpcError && e.kind === "forbidden" && /not allowed/.test(e.message));
});

test("chunks arriving out of order are put back together", async () => {
  const sent = []; const rpc = createRpc({ send: (m) => sent.push(m) });
  const p = rpc.request("snapshot");
  const whole = new TextEncoder().encode(JSON.stringify({ id: sent[0].id, type: "ack", version: 1, payload: { text: "ñandú ".repeat(50) } }));
  const cut = [whole.slice(0, 100), whole.slice(100, 220), whole.slice(220)];
  for (const i of [2, 0, 1]) rpc.receive({ id: sent[0].id, type: "chunk", version: 1, payload: { index: i, total: 3, data: b64(cut[i]) } });
  assert.equal((await p).text, "ñandú ".repeat(50));
});

test("a missing chunk leaves the request to time out; junk chunks are ignored", async () => {
  const t = fakeTimers(); const sent = [];
  const rpc = createRpc({ send: (m) => sent.push(m), ...t });
  const p = rpc.request("snapshot");
  rpc.receive({ id: sent[0].id, type: "chunk", payload: { index: 0, total: 2, data: b64([123]) } });
  rpc.receive({ id: sent[0].id, type: "chunk", payload: { index: 9, total: 2, data: "x" } });
  rpc.receive({ id: sent[0].id, type: "chunk", payload: null });
  t.fire();
  await assert.rejects(p, { kind: "no-answer" });
});

test("failAll rejects everything waiting; a failing send rejects at once", async () => {
  const rpc = createRpc({ send: () => {} });
  const a = rpc.request("read", {}); const b = rpc.request("read", {});
  rpc.failAll();
  await assert.rejects(a, { kind: "link-lost" }); await assert.rejects(b, { kind: "link-lost" });
  const broken = createRpc({ send: () => { throw new Error("socket closed"); } });
  await assert.rejects(broken.request("read", {}), { kind: "send-failed", message: "socket closed" });
  assert.equal(broken.pending(), 0);
});
