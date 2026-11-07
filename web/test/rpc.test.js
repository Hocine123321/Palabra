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

import { relayBase, openLink } from "../src/link-client.js";

test("relay addresses are tidied, and obvious mistakes are explained", () => {
  assert.equal(relayBase("wss://palabra-relay.me.workers.dev/"), "wss://palabra-relay.me.workers.dev");
  assert.equal(relayBase("https://palabra-relay.me.workers.dev"), "wss://palabra-relay.me.workers.dev");   // typed from the browser bar
  assert.equal(relayBase("palabra-relay.me.workers.dev"), "wss://palabra-relay.me.workers.dev");
  assert.equal(relayBase("ws://localhost:8787"), "ws://localhost:8787");
  for (const bad of ["", "wss://nodots", "wss://has space.com", "wss://"]) assert.throws(() => relayBase(bad), (e) => e.kind === "relay-address");
});

/** A socket that behaves like a browser's when the address is wrong: it never opens, and maybe closes or says nothing. */
class DeadSocket {
  constructor(how) { this.how = how; this.listeners = {}; queueMicrotask(() => { if (how === "close") this.fire("close", { code: 1006 }); if (how === "error") this.fire("error", {}); if (how === "full") this.fire("close", { code: 4001 }); }); }
  addEventListener(e, f) { (this.listeners[e] ??= []).push(f); }
  fire(e, ev) { for (const f of this.listeners[e] ?? []) f(ev); }
  close() {}
}

test("a relay that never opens is a failure with a reason, never an endless 'Connecting'", async () => {
  const secret = new Uint8Array(32).fill(1);
  const cases = { silent: "relay-timeout", close: "relay", error: "relay", full: "room-full" };
  for (const [how, kind] of Object.entries(cases)) {
    await assert.rejects(openLink({ relayUrl: "wss://r.example", secret, WebSocketImpl: class extends DeadSocket { constructor() { super(how); } }, connectTimeoutMs: 40 }), (e) => e.kind === kind, how);
  }
});
