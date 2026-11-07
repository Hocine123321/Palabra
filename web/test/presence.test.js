// The permanent fix for "waiting for the phone / waiting for the browser": roles, presence and a heartbeat.
import test from "node:test";
import assert from "node:assert/strict";
import { openLink } from "../src/link-client.js";
import { createSync } from "../src/sync.js";
import { createCache, memoryStore } from "../src/cache.js";
import { Session, randomBytes, roomId } from "../src/link-crypto.js";

const tick = () => new Promise((r) => setImmediate(r));
const until = async (check, what, ms = 3000) => { const end = Date.now() + ms; while (Date.now() < end) { if (check()) return; await new Promise((r) => setTimeout(r, 2)); } throw new Error("never reached: " + what); };
const buffer = (u8) => u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);

/** A relay socket we control: tests push frames in and read what the page sent. */
function controlledSocket() {
  const made = [];
  class Socket {
    constructor(url) { this.url = String(url); this.h = {}; this.sent = []; this.closedWith = null; made.push(this); queueMicrotask(() => this.fire("open", {})); }
    addEventListener(t, f) { (this.h[t] ??= []).push(f); }
    fire(t, e) { for (const f of [...(this.h[t] ?? [])]) f(e); }
    send(d) { this.sent.push(d); }
    close(code) { this.closedWith = code ?? 1000; this.fire("close", { code: code ?? 1000 }); }
    say(text) { this.fire("message", { data: text }); }
  }
  return { Socket, made };
}

function clock() {
  let t = 0; const beats = [];
  return {
    nowMs: () => t, advance: (ms) => { t += ms; },
    setRepeat: (fn) => { beats.push(fn); return beats.length; }, clearRepeat: (i) => { beats[i - 1] = null; },
    beat: () => { for (const b of beats) b?.(); },
    setTimer: () => 0, clearTimer() {},
  };
}

const base = (c, s, extra = {}) => ({ relayUrl: "wss://relay.example", secret: randomBytes(32), WebSocketImpl: s.Socket, setTimer: c.setTimer, clearTimer: c.clearTimer, setRepeat: c.setRepeat, clearRepeat: c.clearRepeat, nowMs: c.nowMs, ...extra });

test("the page sits in the browser's seat of its room", async () => {
  const s = controlledSocket(), c = clock();
  const secret = randomBytes(32);
  await openLink(base(c, s, { secret }));
  assert.equal(s.made[0].url, `wss://relay.example/r/${await roomId(secret)}?role=web`);
});

test("the relay's notices say whether the phone is there, and an older relay that says nothing leaves it unknown", async () => {
  const s = controlledSocket(), c = clock(); const seen = [];
  const link = await openLink(base(c, s, { onPeer: (h) => seen.push(h) }));
  assert.equal(link.peerHere, null, "unknown until the relay says");
  s.made[0].say("peer:here"); assert.equal(link.peerHere, true);
  s.made[0].say("peer:gone"); assert.equal(link.peerHere, false);
  s.made[0].say("something else"); assert.equal(link.peerHere, false, "anything else is ignored");
  assert.deepEqual(seen, [true, false]);
});

test("a socket that goes silent is closed by the page so it reconnects instead of waiting on a dead connection", async () => {
  const s = controlledSocket(), c = clock(); let lost = 0;
  await openLink(base(c, s, { onClose: () => { lost++; } }));
  c.advance(30000); c.beat();
  assert.equal(s.made[0].closedWith, null, "quiet for 30 s is still fine");
  c.advance(25000); c.beat();
  assert.equal(s.made[0].closedWith, 1000, "silent for 55 s: closed");
  assert.equal(lost, 1, "and the caller is told, so it reconnects");
});

test("anything heard from the relay keeps the link alive", async () => {
  const s = controlledSocket(), c = clock(); let lost = 0;
  await openLink(base(c, s, { onClose: () => { lost++; } }));
  for (let i = 0; i < 10; i++) { c.advance(20000); s.made[0].say("peer:here"); c.beat(); }
  assert.equal(s.made[0].closedWith, null);
  assert.equal(lost, 0);
});

test("being replaced by a newer page of ours does not start a reconnect war", async () => {
  const s = controlledSocket(), c = clock(); let lost = 0;
  await openLink(base(c, s, { onClose: () => { lost++; } }));
  s.made[0].close(4005);
  assert.equal(lost, 0);
});

test("closing on purpose is not a lost link", async () => {
  const s = controlledSocket(), c = clock(); let lost = 0;
  const link = await openLink(base(c, s, { onClose: () => { lost++; } }));
  link.close();
  assert.equal(lost, 0);
});

// ---- sync: no more passing the phone in the retry gaps ----

function syncHarness(link) {
  const seen = []; const timers = [];
  const sync = createSync({
    cache: createCache(memoryStore()), onChange: (v) => seen.push(v),
    openLink: async (o) => { link.options = o; return link; },
    setTimer: (fn, ms) => { timers.push({ fn, ms }); return timers.length; }, clearTimer() {},
  });
  return { sync, seen, timers, last: () => seen[seen.length - 1] };
}

const FRESH = { snapshot: { words: [{ id: "1" }] }, takenAt: "2026-11-07T10:00:00Z" };

test("the phone is not there yet: the page stays connected, says so, and fills in the moment the phone arrives", async () => {
  let asked = 0;
  const link = { peerHere: false, request: async () => { asked++; return FRESH; }, close() {} };
  const h = syncHarness(link);
  await h.sync.start("ab".repeat(32), "wss://r");
  assert.equal(h.last().state, "empty");
  assert.equal(h.last().reason, "phone-away");
  assert.equal(asked, 0, "no blind request into an empty room");
  assert.equal(h.timers.length, 0, "and no retry timer to sleep through the phone's arrival");

  link.peerHere = true;
  link.options.onPeer(true);
  await tick();
  assert.equal(h.last().state, "linked");
  assert.equal(asked, 1);
});

test("the phone leaves and returns: away, then linked again without any timer", async () => {
  const link = { peerHere: true, request: async () => FRESH, close() {} };
  const h = syncHarness(link);
  await h.sync.start("ab".repeat(32), "wss://r");
  assert.equal(h.last().state, "linked");
  link.options.onPeer(false);
  assert.equal(h.last().state, "away");
  link.options.onPeer(true); await tick();
  assert.equal(h.last().state, "linked");
  assert.equal(h.timers.length, 0);
});

test("a relay that reports nothing about presence still gets a direct request, as before", async () => {
  const link = { peerHere: null, request: async () => FRESH, close() {} };
  const h = syncHarness(link);
  await h.sync.start("ab".repeat(32), "wss://r");
  assert.equal(h.last().state, "linked");
});

test("the phone's arrival notice that comes while the page is still opening is not lost", async () => {
  const link = { peerHere: null, request: async () => FRESH, close() {} };
  const seen = [];
  const sync = createSync({
    cache: createCache(memoryStore()), onChange: (v) => seen.push(v),
    openLink: async (o) => { o.onPeer(true); return link; },     // announced before openLink even returns
    setTimer: () => 0, clearTimer() {},
  });
  await sync.start("ab".repeat(32), "wss://r");
  assert.equal(seen.at(-1).state, "linked");
});

test("the phone is present but the first request is lost: the page retries on the SAME socket and still ends up linked", async () => {
  let calls = 0;
  const link = { peerHere: true, request: async () => { calls++; if (calls === 1) throw Object.assign(new Error("silent"), { kind: "no-answer" }); return FRESH; }, close() {} };
  const h = syncHarness(link);
  await h.sync.start("ab".repeat(32), "wss://r");
  assert.notEqual(h.last().state, "linked");
  assert.equal(h.timers.length, 1, "a retry is scheduled");
  await h.timers[0].fn(); await tick();
  assert.equal(h.last().state, "linked");
});

// ---- per-computer trust: the browser says who it is, and a removed computer is cut off for good ----

import { createRpc } from "../src/link-rpc.js";

test("a browser paired with the code sends no hello at all", async () => {
  const s = controlledSocket(), c = clock();
  const link = await openLink(base(c, s));
  await link.introduce();
  assert.equal(s.made[0].sent.length, 0);
});

test("a trusted computer introduces itself with its token and carries on when accepted", async () => {
  const secret = randomBytes(32);
  const app = await Session.open(secret, "app");
  const s = controlledSocket(), c = clock();
  const link = await openLink(base(c, s, { secret, tokenHex: "ab".repeat(32) }));
  const pending = link.introduce();
  await until(() => s.made[0].sent.length > 0, "the hello was sent");
  const sent = await app.open(s.made[0].sent[0]);
  assert.equal(sent.type, "hello");
  assert.equal(sent.payload.token, "ab".repeat(32));
  const answer = await app.seal({ id: sent.id, type: "ack", version: 1, payload: {} });
  s.made[0].fire("message", { data: buffer(answer) });
  await pending;
});

test("a computer the phone no longer trusts is told 'revoked', the page stops retrying and says why", async () => {
  const secret = randomBytes(32);
  const secretHex = Array.from(secret, (b) => b.toString(16).padStart(2, "0")).join("");
  const app = await Session.open(secret, "app");
  const s = controlledSocket(), c = clock();
  const seen = [], timers = [];
  const sync = createSync({
    cache: createCache(memoryStore()), onChange: (v) => seen.push(v),
    openLink: (o) => openLink({ ...base(c, s), ...o, tokenHex: "cd".repeat(32) }),      // the sync's own secret and relay win
    setTimer: (fn, ms) => { timers.push({ fn, ms }); return timers.length; }, clearTimer() {},
  });
  const started = sync.start(secretHex, "wss://relay.example");
  await until(() => s.made[0]?.sent.length > 0, "the hello was sent");
  const hello = await app.open(s.made[0].sent[0]);
  assert.equal(hello.type, "hello");
  const refusal = await app.seal({ id: hello.id, type: "reject", version: 1, payload: { reason: "revoked" } });
  s.made[0].fire("message", { data: buffer(refusal) });
  await started; await tick();
  assert.equal(seen.at(-1).state, "error");
  assert.match(seen.at(-1).message, /no longer trusted/);
  assert.equal(timers.length, 0, "no retry for something only the person can fix");
});
