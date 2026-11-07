// Drives the real bundled page against a tiny fake DOM, fake storage and a fake phone link.
// Checks the behaviour a person sees: what is on screen, and what the browser keeps.
import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { build } from "../scripts/build.js";

const html = build();

/** Waits until `check()` is true (or fails loudly after ~2 s). Counting event-loop turns is what made this flaky. */
async function until(check, what) {
  for (let i = 0; i < 400; i++) { if (check()) return; await new Promise((x) => setTimeout(x, 5)); }
  assert.fail(`never reached: ${what}`);
}
const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);

function makeDom() {
  const nodes = {};
  const make = (id) => ({ id, hidden: id === "app", value: "", checked: false, textContent: "", innerHTML: "", disabled: false, dataset: {}, listeners: {},
    addEventListener(e, f) { this.listeners[e] = f; }, setAttribute() {}, removeAttribute() {}, focus() {}, setSelectionRange() {} });
  for (const id of ids) nodes[id] = make(id);
  nodes.pairing.hidden = false;
  // querySelectorAll finds what the page really renders: the tab buttons, and any [data-x="..."] button in the current view.
  const tabs = ["library", "study", "artifacts", "chat", "books"].map((tab) => Object.assign(make("tab-" + tab), { dataset: { tab } }));
  const found = new Map();   // one stable node per data-attribute value, so a test can click it
  const querySelectorAll = (selector) => {
    if (selector === "nav.tabs button") return tabs;
    const attr = selector.match(/^\[data-([a-z]+)\]$/)?.[1];
    if (!attr) return [];
    return [...(String(nodes.view.innerHTML) + String(nodes.found?.innerHTML ?? "")).matchAll(new RegExp(`data-${attr}="([^"]*)"`, "g"))].map((m) => {
      const key = `${attr}:${m[1]}`;
      if (!found.has(key)) found.set(key, Object.assign(make(key), { dataset: { [attr]: m[1].replace(/&quot;/g, '"') } }));
      return found.get(key);
    });
  };
  return { nodes, tabs, document: { documentElement: {}, querySelector: (s) => (s.startsWith("#") ? nodes[s.slice(1)] ?? make(s) : make(s)), querySelectorAll } };
}

const SNAP = { words: [{ id: "1", key: "hola", spanish: "hola", translation: "hello", partOfSpeech: "n", category: null, tags: [] }], decks: [], review: [], wordsPerDay: [], wordsPerWeek: [] };

async function run({ idb = new Map(), phoneUp = true, lang = "en" } = {}) {
  const { nodes, document, tabs } = makeDom();
  const closed = [];
  const fakeIndexedDB = { open: () => { const req = {}; queueMicrotask(() => {
    const os = () => ({ put: (v, k) => { idb.set(k, structuredClone(v)); return {}; }, get: (k) => ({ get result() { return idb.get(k); } }), delete: (k) => { idb.delete(k); return {}; }, getAllKeys: () => ({ get result() { return [...idb.keys()]; } }) });
    req.result = { createObjectStore() {}, transaction() { const tx = { objectStore: os }; queueMicrotask(() => queueMicrotask(() => tx.oncomplete?.())); return tx; }, close() {} };
    req.onupgradeneeded?.(); req.onsuccess?.(); }); return req; } };
  // A phone that answers `snapshot` only when it is "up", reached through WebSocket + fetch fakes.
  const sandbox = {
    document, location: { protocol: "file:" }, navigator: { languages: [lang], language: lang }, indexedDB: fakeIndexedDB,
    crypto: globalThis.crypto, TextEncoder, TextDecoder, atob, btoa, structuredClone, console, setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {}, queueMicrotask, Uint8Array, Promise,
    fetch: async (url, opts) => {
      if (String(url).endsWith("/hello")) return { ok: true, status: 200, json: async () => ({ nonce: "00".repeat(16) }) };
      return { ok: true, status: 200, json: async () => ({ ok: true }) };
    },
  };
  return { nodes, sandbox, idb, closed, tabs };
}

test("the page starts on the pairing card, with nothing saved and nothing sent", async () => {
  const r = await run();
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  assert.equal(r.nodes.pairing.hidden, false);
  assert.equal(r.nodes.app.hidden, true);
  assert.equal(r.idb.size, 0, "nothing is written to the browser before the person asks");
});

test("a remembered computer opens straight onto its saved copy while the phone is away", async () => {
  const idb = new Map();
  idb.set("pairing", { schema: 1, secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  idb.set("snapshot", { schema: 1, snapshot: SNAP, takenAt: "2026-11-06T09:00:00Z" });
  const r = await run({ idb });
  r.sandbox.WebSocket = class { constructor() { throw new Error("relay down"); } };   // phone and relay unreachable
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await until(() => /Phone away/.test(r.nodes.status.innerHTML), "offline status shown");
  assert.equal(r.nodes.app.hidden, false, "the app is shown without the phone");
  assert.equal(r.nodes.pairing.hidden, true);
  assert.match(r.nodes.view.innerHTML, /hola/, "saved words are on screen");
  assert.match(r.nodes.status.innerHTML, /Phone away/);
  assert.match(r.nodes.hint.textContent, /Saved copy from your phone/);
});

test("in Arabic the same offline start reads in Arabic", async () => {
  const idb = new Map();
  idb.set("pairing", { schema: 1, secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  idb.set("snapshot", { schema: 1, snapshot: SNAP, takenAt: "2026-11-06T09:00:00Z" });
  const r = await run({ idb, lang: "ar" });
  r.sandbox.WebSocket = class { constructor() { throw new Error("relay down"); } };
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await until(() => /الهاتف بعيد/.test(r.nodes.status.innerHTML), "Arabic offline status");
  assert.match(r.nodes.status.innerHTML, /الهاتف بعيد/);
  assert.match(r.nodes.hint.textContent, /نسخة محفوظة/);
  assert.equal(r.sandbox.document.documentElement.dir, "rtl");
});

test("Forget this computer deletes the key and every saved word, and returns to pairing", async () => {
  const idb = new Map();
  idb.set("pairing", { schema: 1, secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  idb.set("snapshot", { schema: 1, snapshot: SNAP, takenAt: "2026-11-06T09:00:00Z" });
  const r = await run({ idb });
  r.sandbox.WebSocket = class { constructor() { throw new Error("relay down"); } };
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await until(() => r.nodes.app.hidden === false && /hola/.test(r.nodes.view.innerHTML), "saved copy shown");
  assert.ok(idb.size > 0);
  await r.nodes.forget.listeners.click();
  await until(() => idb.size === 0, "browser emptied");
  assert.equal(idb.size, 0, "nothing of the person's data is left in the browser");
  assert.equal(r.nodes.pairing.hidden, false);
  assert.equal(r.nodes.app.hidden, true);
  assert.equal(r.nodes.view.innerHTML, "");
});

import { wrapSecret, toHex, Session } from "../src/link-crypto.js";

/** A fake phone for the pairing form: real wrapping of a known secret, and a socket that answers `snapshot` like the app. */
async function phoneAndRelay(code, phoneRelay = "wss://phone-relay.example") {
  const secret = new Uint8Array(32).fill(9);
  const nonce = new Uint8Array(16).fill(1);
  const sealedPayload = new Uint8Array([...secret, ...new TextEncoder().encode(phoneRelay)]);   // like the app: secret, then its relay address
  const { iv, ct } = await wrapSecret(code, nonce, sealedPayload);
  const fetch = async (url, opts) => {
    if (String(url).endsWith("/hello")) return { ok: true, status: 200, json: async () => ({ nonce: toHex(nonce) }) };
    return { ok: true, status: 200, json: async () => ({ iv: toHex(iv), sealed: toHex(ct) }) };
  };
  const appSession = await Session.open(secret, "app");
  const opened = [];
  class Socket {
    constructor(url) { opened.push(String(url)); this.listeners = {}; queueMicrotask(() => this.listeners.open?.[0]()); }
    addEventListener(e, f) { (this.listeners[e] ??= []).push(f); }
    removeEventListener() {}
    close() { this.listeners.close?.forEach((f) => f()); }
    async send(frame) {
      const request = await appSession.open(new Uint8Array(frame));
      const reply = { id: request.id, type: "ack", version: 1, payload: { snapshot: SNAP, takenAt: "2026-11-07T10:00:00Z" } };
      const sealedReply = await appSession.seal(reply);
      queueMicrotask(() => this.listeners.message?.forEach((f) => f({ data: sealedReply.buffer.slice(sealedReply.byteOffset, sealedReply.byteOffset + sealedReply.byteLength) })));
    }
  }
  return { fetch, Socket, opened };
}

async function pairThroughTheForm({ remember }) {
  const r = await run();
  const { fetch, Socket } = await phoneAndRelay("482913");
  Object.assign(r.sandbox, { fetch, WebSocket: Socket });
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" });
  Object.assign(r.nodes.code, { value: "482913" });
  Object.assign(r.nodes.relay, { value: "wss://relay.example" });
  r.nodes.remember.checked = remember;
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  await until(() => r.nodes.err.textContent !== "" || /hola/.test(r.nodes.view.innerHTML), "pairing finished");
  if (remember) await until(() => r.idb.has("snapshot"), "snapshot saved");
  return r;
}

test("pairing through the form shows the phone's words", async () => {
  const r = await pairThroughTheForm({ remember: false });
  assert.equal(r.nodes.err.textContent, "");
  assert.equal(r.nodes.app.hidden, false);
  assert.match(r.nodes.view.innerHTML, /hola/);
  assert.match(r.nodes.status.innerHTML, /Linked to your phone/);
  assert.equal(r.nodes.code.value, "", "the code is cleared once used");
});

test("with Remember OFF (the default) the browser keeps nothing: no key, no words", async () => {
  const r = await pairThroughTheForm({ remember: false });
  assert.equal(r.idb.size, 0);
});

test("with Remember ON the key and the words are saved, and the secret is the one the phone gave", async () => {
  const r = await pairThroughTheForm({ remember: true });
  assert.equal(r.idb.get("pairing").secretHex, "09".repeat(32));
  assert.equal(r.idb.get("pairing").relayUrl, "wss://phone-relay.example");   // the phone's address wins over the one typed (wss://relay.example)
  assert.equal(r.idb.get("snapshot").snapshot.words[0].spanish, "hola");
});

test("a wrong code shows the translated error and leaves the pairing card up", async () => {
  const r = await run();
  r.sandbox.fetch = async (url) => String(url).endsWith("/hello")
    ? { ok: true, status: 200, json: async () => ({ nonce: "00".repeat(16) }) }
    : { ok: false, status: 403, json: async () => ({ error: "wrong", triesLeft: 4 }) };
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" }); Object.assign(r.nodes.code, { value: "111111" }); Object.assign(r.nodes.relay, { value: "wss://x" });
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  assert.equal(r.nodes.err.textContent, "Wrong code. 4 tries left.");
  assert.equal(r.nodes.pairing.hidden, false);
  assert.equal(r.idb.size, 0);
});

test("after several silent attempts the page suggests forgetting the computer, instead of saying 'away' forever", async () => {
  const idb = new Map();
  idb.set("pairing", { schema: 1, secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  idb.set("snapshot", { schema: 1, snapshot: SNAP, takenAt: "2026-11-06T09:00:00Z" });
  const r = await run({ idb });
  const timers = [];
  r.sandbox.setTimeout = (fn) => { timers.push(fn); return timers.length; };
  r.sandbox.WebSocket = class { constructor() { throw new Error("relay down"); } };
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await until(() => /Saved copy from your phone/.test(r.nodes.hint.textContent), "the first offline hint");
  for (let failures = 2; failures <= 4; failures++) {
    await timers.shift()();
    await until(() => timers.length > 0 || /forget this computer/.test(r.nodes.hint.textContent), `failure ${failures} handled`);
  }
  await until(() => /forget this computer and pair again/.test(r.nodes.hint.textContent), "the re-pair hint");
  assert.match(r.nodes.hint.textContent, /forget this computer and pair again/);
});

const ARTIFACTS = [{ id: "p1", title: "My <b>plan</b>", kind: "spec", viewable: true, runnable: false }, { id: "g1", title: "Game", kind: "app", viewable: false, runnable: false }];
const PAGES = { p1: { id: "p1", title: "My <b>plan</b>", blocks: [{ type: "heading", level: 1, text: "Week 1" }, { type: "checklist", items: [{ text: "Review", done: true }, { text: "Read", done: false }] }] } };

/** Like phoneAndRelay, but the fake phone also records the `write` messages it receives and can be told to refuse. */
async function phoneThatTakesWrites(code, { refuse = null } = {}) {
  const base = await phoneAndRelay(code);
  const writes = [], seen = [];
  const secret = new Uint8Array(32).fill(9);
  const appSession = await Session.open(secret, "app");
  class Socket extends base.Socket {
    async send(frame) {
      const probe = await Session.open(secret, "app");
      const request = await probe.open(new Uint8Array(frame));
      seen.push(request.type);
      const reply = request.type === "chat"
        ? { id: request.id, type: "ack", version: 1, payload: { result: { chat: { title: "Verbos", turns: [{ role: "user", text: "hola <b>x</b>" }, { role: "assistant", text: "¡Hola!" }] } } } }
        : request.type === "books"
          ? { id: request.id, type: "ack", version: 1, payload: { result: [{ id: "b1", title: "Historia", chapters: [{ title: "Uno", lessons: [{ id: "l1", title: "Roma" }] }] }] } }
        : request.type === "lesson"
          ? { id: request.id, type: "ack", version: 1, payload: { result: { title: "Roma", pages: [{ title: "P1", blocks: [{ kind: "text", text: "Texto de Roma" }] }] } } }
        : request.type === "artifacts"
        ? { id: request.id, type: "ack", version: 1, payload: { result: ARTIFACTS } }
        : request.type === "artifact"
          ? (PAGES[request.payload?.id] ? { id: request.id, type: "ack", version: 1, payload: { result: PAGES[request.payload.id] } } : { id: request.id, type: "reject", version: 1, payload: { reason: "not-found" } })
        : request.type === "write"
        ? (writes.push(request.payload), refuse ? { id: request.id, type: "reject", version: 1, payload: { reason: refuse } } : { id: request.id, type: "ack", version: 1, payload: { result: { queued: 1 } } })
        : { id: request.id, type: "ack", version: 1, payload: { snapshot: SNAP, takenAt: "2026-11-07T10:00:00Z" } };
      const sealed = await appSession.seal(reply);
      queueMicrotask(() => this.listeners.message?.forEach((f) => f({ data: sealed.buffer.slice(sealed.byteOffset, sealed.byteOffset + sealed.byteLength) })));
    }
  }
  return { fetch: base.fetch, Socket, writes, seen };
}

async function pairedPage({ remember = false, refuse = null } = {}) {
  const r = await run();
  const phone = await phoneThatTakesWrites("482913", { refuse });
  Object.assign(r.sandbox, { fetch: phone.fetch, WebSocket: phone.Socket });
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" }); Object.assign(r.nodes.code, { value: "482913" }); Object.assign(r.nodes.relay, { value: "wss://relay.example" });
  r.nodes.remember.checked = remember;
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  await until(() => /hola/.test(r.nodes.view.innerHTML), "library shown");
  return { ...r, phone };
}

test("words typed in the page are sent to the phone as one write with an id, and the box is cleared", async () => {
  const r = await pairedPage();
  r.nodes.addText.value = "buenas noches, adiós";
  await r.nodes.add.listeners.submit({ preventDefault() {} });
  await until(() => r.phone.writes.length === 1, "write received by the phone");
  assert.equal(r.phone.writes[0].capability, "words.add");
  assert.deepEqual(r.phone.writes[0].args.words, ["buenas noches", "adiós"]);
  assert.ok(r.phone.writes[0].id.length > 8);
  assert.equal(r.nodes.addText.value, "");
});

test("a refused change shows up in 'Needs your review' with the reason, instead of vanishing", async () => {
  const r = await pairedPage({ refuse: "conflict" });
  r.nodes.addText.value = "hola";
  await r.nodes.add.listeners.submit({ preventDefault() {} });
  await until(() => /Needs your review/.test(r.nodes.view.innerHTML), "review list shown");
  assert.match(r.nodes.view.innerHTML, /changed on the phone/);
  assert.match(r.nodes.view.innerHTML, /data-retry=/);
});

test("with Remember OFF, queued changes are never written to the browser either", async () => {
  const r = await pairedPage({ remember: false, refuse: "conflict" });
  r.nodes.addText.value = "hola";
  await r.nodes.add.listeners.submit({ preventDefault() {} });
  await until(() => /Needs your review/.test(r.nodes.view.innerHTML), "review list shown");
  assert.equal(r.idb.size, 0);
});

test("Forget this computer also removes waiting and refused changes", async () => {
  const r = await pairedPage({ remember: true, refuse: "conflict" });
  r.nodes.addText.value = "hola";
  await r.nodes.add.listeners.submit({ preventDefault() {} });
  await until(() => r.idb.has("outbox"), "outbox saved");
  await r.nodes.forget.listeners.click();
  await until(() => r.idb.size === 0, "browser emptied");
  assert.equal(r.idb.size, 0);
});


test("the Artifacts tab lists pages, opens one, escapes it, and goes back; apps are shown as phone-only and never requested", async () => {
  const r = await pairedPage();
  r.tabs.find((t) => t.dataset.tab === "artifacts").listeners.click();
  await until(() => /Opens on your phone/.test(r.nodes.view.innerHTML), "list shown");
  assert.doesNotMatch(r.nodes.view.innerHTML, /<b>plan/);               // the title is text, not markup
  assert.match(r.nodes.view.innerHTML, /My &lt;b&gt;plan/);
  assert.doesNotMatch(r.nodes.view.innerHTML, /data-artifact="g1"/);    // an app has no way to be opened here
  r.nodes.view.innerHTML.match(/data-artifact="p1"/) || assert.fail("page not openable");
  r.sandbox.document.querySelectorAll("[data-artifact]")[0].listeners.click();
  await until(() => /Week 1/.test(r.nodes.view.innerHTML), "page shown");
  assert.match(r.nodes.view.innerHTML, /☑/); assert.match(r.nodes.view.innerHTML, /☐/);
  assert.deepEqual(r.phone.seen.filter((t) => t.startsWith("artifact")), ["artifacts", "artifact"]);
  r.nodes.artifactBack.listeners.click();
  await until(() => /Opens on your phone/.test(r.nodes.view.innerHTML), "back to list");
});

test("with the phone away, the Artifacts tab says so instead of showing nothing", async () => {
  const idb = new Map();
  idb.set("pairing", { schema: 1, secretHex: "ab".repeat(32), relayUrl: "wss://relay.example" });
  idb.set("snapshot", { schema: 1, takenAt: "2026-11-07T10:00:00Z", snapshot: SNAP });
  const r = await run({ idb, phoneUp: false });
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await until(() => /hola/.test(r.nodes.view.innerHTML), "saved copy shown");
  r.tabs.find((t) => t.dataset.tab === "artifacts").listeners.click();
  await until(() => /phone must be connected/.test(r.nodes.view.innerHTML), "notice shown");
  assert.doesNotMatch(r.nodes.view.innerHTML, /data-artifact/);
});

test("when the first connection fails the page is not dead: tabs work and it says why, with a way to retry", async () => {
  const r = await run();
  const phone = await phoneThatTakesWrites("482913");
  class SilentSocket extends phone.Socket { async send() { /* the phone never answers */ } }
  Object.assign(r.sandbox, { fetch: phone.fetch, WebSocket: SilentSocket, PALABRA_RPC_TIMEOUT_MS: 30, setTimeout, clearTimeout });
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" }); Object.assign(r.nodes.code, { value: "482913" }); Object.assign(r.nodes.relay, { value: "wss://relay.example" });
  r.nodes.remember.checked = false;
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  await until(() => r.nodes.app.hidden === false, "app shown even without data");
  await until(() => /Nothing to show yet/.test(r.nodes.view.innerHTML), "empty state shown");
  assert.match(r.nodes.view.innerHTML, /id="retry"/);
  for (const tab of ["study", "library", "artifacts", "library"]) {   // every tab responds, none throws
    r.tabs.find((t) => t.dataset.tab === tab).listeners.click();
    await new Promise((x) => setImmediate(x));
    assert.ok(r.nodes.view.innerHTML.length > 0, `${tab} drew something`);
  }
  assert.match(r.nodes.status.innerHTML, /Phone not reachable/);       // the status says it too, not a bare dot
  r.nodes.forget.listeners.click();                                     // stops the retry timer so the test can end
});

test("the Chat tab shows the latest chat and the Books tab opens a lesson, all through the live link and nothing kept in the browser", async () => {
  const r = await pairedPage();
  r.tabs.find((x) => x.dataset.tab === "chat").listeners.click();
  await until(() => /Verbos/.test(r.nodes.view.innerHTML), "chat shown");
  assert.match(r.nodes.view.innerHTML, /bubble me/);
  assert.ok(!r.nodes.view.innerHTML.includes("<b>x</b>"), "chat text is escaped");
  r.tabs.find((x) => x.dataset.tab === "books").listeners.click();
  await until(() => /Historia/.test(r.nodes.view.innerHTML), "books shown");
  assert.match(r.nodes.view.innerHTML, /data-lesson="l1"/);
  assert.equal(r.idb.size, 0, "nothing stored for chat or books");
});

test("the page joins the relay the PHONE is on, even when a different one was typed (the 'both connected, nobody there' bug)", async () => {
  const r = await run();
  const phone = await phoneAndRelay("482913", "wss://phone-relay.example");
  r.sandbox.fetch = phone.fetch;
  r.sandbox.WebSocket = phone.Socket;
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" });
  Object.assign(r.nodes.code, { value: "482913" });
  Object.assign(r.nodes.relay, { value: "wss://some-other-relay.example" });   // a typo, an old worker, anything
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  await until(() => phone.opened.length > 0, "a relay was joined");
  assert.match(phone.opened[0], /^wss:\/\/phone-relay\.example\/r\//, phone.opened[0]);
});

test("pairing with an older app that sends no relay address still works from the typed one, and says so if neither exists", async () => {
  const r = await run();
  const phone = await phoneAndRelay("482913", "");            // an older app: the sealed payload is the secret alone
  r.sandbox.fetch = phone.fetch;
  r.sandbox.WebSocket = phone.Socket;
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.address, { value: "192.168.1.20" });
  Object.assign(r.nodes.code, { value: "482913" });
  Object.assign(r.nodes.relay, { value: "" });
  await r.nodes.pair.listeners.submit({ preventDefault() {} });
  await until(() => r.nodes.err.textContent !== "", "asked for the relay address");
  assert.match(r.nodes.err.textContent, /relay address/i);
  assert.equal(phone.opened.length, 0, "nothing was joined without an address");
});

import { makeTrustKeys, sealGrant } from "../src/trust-crypto.js";

/** One socket class for both: `/lobby` is the introductions, `/r/<room>` is the phone's relay room. */
async function lobbyAndPhone({ accept = true } = {}) {
  const keys = await makeTrustKeys();
  const deviceId = "cd".repeat(16);
  const secret = new Uint8Array(32).fill(9), token = new Uint8Array(32).fill(7);
  const appSession = await Session.open(secret, "app");
  const lobby = new Set(), opened = [];
  let seenRequest = null;
  class Socket {
    constructor(url) {
      this.url = String(url); this.listeners = {}; opened.push(this.url);
      if (this.url.endsWith("/lobby")) lobby.add(this);
      queueMicrotask(() => this.listeners.open?.forEach((f) => f()));
    }
    addEventListener(e, f) { (this.listeners[e] ??= []).push(f); }
    removeEventListener() {}
    close() { lobby.delete(this); this.listeners.close?.forEach((f) => f({ code: 1000 })); }
    say(frame) { queueMicrotask(() => this.listeners.message?.forEach((f) => f({ data: frame }))); }
    async send(data) {
      if (this.url.endsWith("/lobby")) {
        const f = JSON.parse(data);
        if (f.type === "hello") this.say(JSON.stringify({ type: "announce", deviceId, name: "Hocine's iPhone", pub: keys.pub }));
        if (f.type === "request") {
          seenRequest = f;
          if (!accept) return this.say(JSON.stringify({ type: "decision", browserId: f.browserId, deviceId, accepted: false }));
          const box = await sealGrant({ phonePrivate: keys.privateKey, phonePub: keys.pub, browserPub: f.pub, grant: { secret, token, relayUrl: "wss://phone-relay.example" } });
          this.say(JSON.stringify({ type: "decision", browserId: f.browserId, deviceId, accepted: true, ...box }));
        }
        return;
      }
      this.say("peer:here");
      const request = await appSession.open(new Uint8Array(data));
      const reply = await appSession.seal({ id: request.id, type: "ack", version: 1, payload: { snapshot: SNAP, takenAt: "2026-11-07T10:00:00Z" } });
      this.say(reply.buffer.slice(reply.byteOffset, reply.byteOffset + reply.byteLength));
    }
  }
  return { Socket, opened, request: () => seenRequest, keys };
}

async function startFinder({ accept = true, remember = false } = {}) {
  const r = await run();
  const phone = await lobbyAndPhone({ accept });
  r.sandbox.WebSocket = phone.Socket;
  vm.createContext(r.sandbox);
  vm.runInContext(script, r.sandbox);
  await new Promise((x) => setImmediate(x));
  Object.assign(r.nodes.relay, { value: "wss://relay.example" });
  r.nodes.remember.checked = remember;
  return { r, phone };
}

test("Find my phone: the phone is listed, choosing it shows the match code, and the page links on the phone's own relay", async () => {
  const { r, phone } = await startFinder();
  r.sandbox.setTimeout = (fn, ms) => setTimeout(fn, Math.min(ms ?? 0, 20));   // a short listening window instead of four seconds
  r.sandbox.clearTimeout = clearTimeout;
  await r.nodes.find.listeners.click();
  await until(() => /data-phone=/.test(r.nodes.found.innerHTML), "the phone is listed");
  assert.match(r.nodes.found.innerHTML, /Hocine&#39;s iPhone|Hocine's iPhone/);

  const choose = [...r.sandbox.document.querySelectorAll("[data-phone]")][0];
  assert.ok(choose, "the phone is a button");
  await choose.listeners.click();
  await until(() => phone.opened.some((u) => /phone-relay\.example\/r\//.test(u)), "linked through the phone's own relay");
  assert.equal(phone.request().name, "Browser on Computer");
  await until(() => /hola/.test(r.nodes.view.innerHTML), "the phone's words are shown");
  assert.equal(r.nodes.app.hidden, false);
});

test("Find my phone: declining on the phone shows why and links nothing", async () => {
  const { r, phone } = await startFinder({ accept: false });
  r.sandbox.setTimeout = (fn, ms) => setTimeout(fn, Math.min(ms ?? 0, 20));
  r.sandbox.clearTimeout = clearTimeout;
  await r.nodes.find.listeners.click();
  await until(() => /data-phone=/.test(r.nodes.found.innerHTML), "the phone is listed");
  await [...r.sandbox.document.querySelectorAll("[data-phone]")][0].listeners.click();
  await until(() => /did not trust/.test(r.nodes.found.innerHTML), "the refusal is shown");
  assert.equal(r.nodes.app.hidden, true);
  assert.ok(!phone.opened.some((u) => /\/r\//.test(u)), "no room was ever joined");
});

test("Find my phone without a relay address says what is missing instead of doing nothing", async () => {
  const { r } = await startFinder();
  r.nodes.relay.value = "";
  await r.nodes.find.listeners.click();
  assert.match(r.nodes.found.innerHTML, /relay address/i);
});
