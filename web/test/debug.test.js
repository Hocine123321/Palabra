import test from "node:test";
import assert from "node:assert/strict";
import { createDebugLog, scrub, describeMessage, MAX_ENTRIES } from "../src/debug-log.js";
import { environmentFacts, mountDebugPanel } from "../src/ui/debug-panel.js";
import { openLink } from "../src/link-client.js";
import { randomBytes, Session } from "../src/link-crypto.js";

const SECRET_HEX = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90";

test("long hex runs (secrets, tokens, keys) are cut to a fingerprint", () => {
  const out = scrub(`secret=${SECRET_HEX} token=${"ab".repeat(32)}`);
  assert.ok(!out.includes(SECRET_HEX), out);
  assert.ok(!out.includes("ab".repeat(32)), out);
  assert.match(out, /a1b2…\(64\)/);
});

test("relay URLs lose their path and query, because the room id is derived from the secret", () => {
  const out = scrub("wss://palabra-relay.me.workers.dev/r/0123456789abcdef0123456789abcdef0123456789abcdef?role=web");
  assert.equal(out, "wss://palabra-relay.me.workers.dev/…");
});

test("long base64 looking runs are cut too, and very long text is capped", () => {
  assert.ok(!scrub("x".repeat(60)).includes("x".repeat(60)));
  assert.ok(scrub("word ".repeat(500)).length <= 401);
});

test("short ordinary words and numbers stay readable", () => {
  assert.equal(scrub("attempt 3 of 4, reason phone-away"), "attempt 3 of 4, reason phone-away");
});

test("a message is described by type, id and size, never by content", () => {
  const text = describeMessage({ id: "q7", type: "read", version: 1, payload: { capability: "library", args: { word: "mariposa-secreta" } } });
  assert.match(text, /^read #q7 \(\d+ B\)$/);
  assert.ok(!text.includes("mariposa"));
  assert.match(describeMessage({ id: "q8", type: "reject", payload: { reason: "revoked" } }), /reason=revoked/);
  assert.equal(describeMessage(null), "unreadable message");
});

test("entries keep order and time, and the oldest are dropped past the cap", () => {
  let t = 1000; const log = createDebugLog({ now: () => (t += 50), max: 5 });
  for (let i = 0; i < 8; i++) log.info("a", `event ${i}`);
  assert.equal(log.size, 5);
  assert.deepEqual(log.entries.map((e) => e.text), ["event 3", "event 4", "event 5", "event 6", "event 7"]);
  assert.ok(MAX_ENTRIES >= 300);
});

test("the text form has one line per entry with level marks, and filters by text and level", () => {
  const log = createDebugLog();
  log.info("link", "socket open"); log.warn("heartbeat", "ping not answered"); log.error("sync", "stopped", "revoked");
  assert.equal(log.toText().split("\n").length, 3);
  assert.match(log.toText({ filter: "HEARTBEAT" }), /ping not answered/);
  assert.equal(log.toText({ level: "error" }).split("\n").length, 1);
  assert.equal(log.toText({ level: "warn" }).split("\n").length, 2);
  assert.match(log.toText({ level: "error" }), /ERR .*\[sync\] stopped \| revoked/);
});

test("a listener that throws cannot break logging, and pausing stops recording", () => {
  const log = createDebugLog(); let seen = 0;
  log.onEntry(() => { throw new Error("broken view"); }); log.onEntry(() => { seen += 1; });
  log.info("a", "one"); assert.equal(seen, 1);
  log.pause(true); log.info("a", "two"); assert.equal(log.size, 1);
  log.pause(false); log.info("a", "three"); assert.equal(log.size, 2);
});

test("the sink given to lower layers records at the chosen level", () => {
  const log = createDebugLog(); log.sink("warn")("x", "careful"); assert.equal(log.entries[0].level, "warn");
});

test("the environment facts name the things that usually explain a connection problem", () => {
  const facts = environmentFacts({ location: { protocol: "file:", host: "" }, isSecureContext: false, navigator: { onLine: false, language: "ar", userAgent: "UA" }, WebSocket() {} , crypto: {} }).map((f) => f[1]).join("\n");
  assert.match(facts, /file:/); assert.match(facts, /secure context: NO/); assert.match(facts, /crypto.subtle: MISSING/); assert.match(facts, /online: NO/);
});

// ---- what the link really records ----

class Sock {
  constructor() { this.h = {}; this.sent = []; Sock.made.push(this); queueMicrotask(() => this.fire("open", {})); }
  addEventListener(t, f) { (this.h[t] ??= []).push(f); } fire(t, e) { for (const f of this.h[t] ?? []) f(e); }
  send(d) { this.sent.push(d); } close(code = 1000) { this.fire("close", { code }); }
}
Sock.made = [];
const until = async (check, what, ms = 3000) => { const end = Date.now() + ms; while (Date.now() < end) { if (check()) return; await new Promise((r) => setTimeout(r, 2)); } throw new Error("never reached: " + what); };
const buf = (u8) => u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);

test("a real conversation with the phone is on record, and nothing secret or personal is in it", async () => {
  Sock.made.length = 0;
  const secret = randomBytes(32), secretHex = Array.from(secret, (b) => b.toString(16).padStart(2, "0")).join("");
  const phone = await Session.open(secret, "app");
  const log = createDebugLog();
  const link = await openLink({ relayUrl: "wss://relay.example", secret, WebSocketImpl: Sock, setTimer: () => 0, clearTimer() {}, setRepeat: () => 1, clearRepeat() {}, log: log.sink(), tokenHex: "cd".repeat(32) });
  const ws = Sock.made[0];
  ws.fire("message", { data: "peer:here" });
  const asked = link.request("read", { capability: "library", args: { word: "mariposa-secreta" } });
  await until(() => ws.sent.length > 0, "request sent");
  const request = await phone.open(ws.sent[0]);
  ws.fire("message", { data: buf(await phone.seal({ id: request.id, type: "ack", version: 1, payload: { words: ["mariposa-secreta"] } })) });
  await asked;
  ws.fire("message", { data: "peer:gone" });
  ws.fire("message", { data: new Uint8Array(80).buffer });         // junk frame
  await until(() => log.toText().includes("dropped"), "the junk frame is noted");
  ws.close(1006);
  const text = log.toText();
  for (const expect of [/opening a socket to the relay \(wss:\/\/relay.example\), seat=web, trusted=yes/, /socket open/, /the phone is in the room/, /tx.*to phone: read #\S+ \(\d+ B\)/, /rx.*from phone: ack #\S+/, /left the room/, /dropped/, /socket closed \(code 1006/]) assert.match(text, expect);
  assert.ok(!text.includes("mariposa"), "no words from the library in the log");
  assert.ok(!text.includes(secretHex), "no secret in the log");
  assert.ok(!text.includes("cd".repeat(32)), "no token in the log");
  assert.ok(!/\/r\/[0-9a-f]{20}/.test(text), "no room id in the log");
});

test("a link that cannot connect says why", async () => {
  const log = createDebugLog();
  class Dead { constructor() { this.h = {}; queueMicrotask(() => (this.h.error ?? []).forEach((f) => f({}))); } addEventListener(t, f) { (this.h[t] ??= []).push(f); } send() {} close() {} }
  await assert.rejects(openLink({ relayUrl: "wss://relay.example", secret: randomBytes(32), WebSocketImpl: Dead, setTimer: () => 0, clearTimer() {}, setRepeat: () => 1, clearRepeat() {}, log: log.sink() }));
  assert.match(log.toText(), /could not connect: relay \| Could not reach the relay/);
});

// ---- the panel, on a tiny DOM stand-in ----

function el(tag) {
  const node = { tag, children: [], attrs: {}, listeners: {}, hidden: false, value: "", textContent: "", _html: "", className: "", classList: { add() {} } };
  node.append = (...kids) => { node.children.push(...kids); };
  node.remove = () => {};
  node.setAttribute = (k, v) => { node.attrs[k] = v; };
  node.addEventListener = (type, fn) => { (node.listeners[type] ??= []).push(fn); };
  node.focus = () => {};
  node.fire = (type, ev = {}) => { for (const f of node.listeners[type] ?? []) f(ev); };
  node.scrollTop = 0; node.scrollHeight = 0; node.clientHeight = 0;
  const parts = {};
  node.querySelector = (selector) => (parts[selector] ??= Object.assign(el("part"), { hidden: selector === ".debug-details" }));   // as the markup has it: details start hidden
  Object.defineProperty(node, "innerHTML", { get: () => node._html, set: (v) => { node._html = v; } });
  return node;
}

test("the Debug button opens a panel that shows the log, filters it, copies it and clears it", async () => {
  const doc = { createElement: el, body: el("body") };
  const log = createDebugLog(); log.info("link", "socket open"); log.warn("heartbeat", "ping not answered");
  let copied = "";
  const ui = mountDebugPanel({ doc, log, t: (k) => k, copyText: async (text) => { copied = text; return true; }, getStatus: () => ({ link: "away", step: "phone", failures: 2, reason: "phone-away" }) });
  try {
  assert.equal(ui.button.attrs["aria-label"], "Debug");
  assert.equal(ui.panel.hidden, true);
  ui.button.fire("click");
  assert.equal(ui.panel.hidden, false);
  assert.equal(ui.panel.querySelector(".debug-title").textContent, "Waiting for your phone", "the panel leads with a plain verdict");
  ui.panel.querySelector('[data-d="more"]').fire("click");        // the details start hidden behind "Show details"
  assert.equal(ui.panel.querySelector(".debug-details").hidden, false);
  const view = ui.panel.querySelector(".debug-log");
  assert.match(view.textContent, /socket open/); assert.match(view.textContent, /ping not answered/);
  log.error("sync", "a new thing happens");
  assert.match(view.textContent, /a new thing happens/, "new entries appear live while open");
  ui.panel.querySelector('[data-d="filter"]').value = "heartbeat";
  ui.panel.querySelector('[data-d="filter"]').fire("input");
  assert.ok(!view.textContent.includes("socket open") && view.textContent.includes("ping not answered"));
  ui.panel.querySelector('[data-d="copy"]').fire("click");
  await new Promise((r) => setTimeout(r, 5));
  assert.match(copied, /^Palabra web debug log/); assert.match(copied, /link=away step=phone failures=2 reason=phone-away/); assert.match(copied, /socket open/, "copy takes the whole log, not the filtered view");
  ui.panel.querySelector('[data-d="clear"]').fire("click");
  assert.ok(!view.textContent.includes("socket open"));
  ui.panel.querySelector('[data-d="close"]').fire("click");
  assert.equal(ui.panel.hidden, true);
  } finally { ui.destroy(); }      // the ticker must never outlive a failing test
});
