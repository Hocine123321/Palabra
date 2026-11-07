import test from "node:test";
import assert from "node:assert/strict";
import { findPhones, requestTrust, computerName } from "../src/auto-pair.js";
import { makeTrustKeys, sealGrant, matchCode } from "../src/trust-crypto.js";
import { randomBytes, toHex } from "../src/link-crypto.js";

/** A lobby in memory: every socket hears every OTHER socket, like the relay. */
function fakeLobby() {
  const sockets = new Set();
  class Socket {
    constructor(url) { this.url = String(url); this.handlers = { message: [], open: [], close: [], error: [] }; sockets.add(this); queueMicrotask(() => this.fire("open", {})); }
    addEventListener(type, fn) { this.handlers[type].push(fn); }
    fire(type, e) { for (const fn of [...this.handlers[type]]) fn(e); }
    send(data) { for (const s of sockets) if (s !== this) queueMicrotask(() => s.fire("message", { data })); }
    close() { sockets.delete(this); }
  }
  return { Socket, sockets };
}

/** A phone that answers hello with an announcement and answers a request with the given decision. */
async function fakePhone(lobby, { accept = true, name = "Hocine's iPhone" } = {}) {
  const keys = await makeTrustKeys();
  const deviceId = toHex(randomBytes(16));
  const secret = randomBytes(32), token = randomBytes(32);
  const socket = new lobby.Socket("wss://relay.example/lobby");
  socket.addEventListener("message", async ({ data }) => {
    const f = JSON.parse(data);
    if (f.type === "hello") socket.send(JSON.stringify({ type: "announce", deviceId, name, pub: keys.pub }));
    if (f.type === "request" && f.to === deviceId) {
      if (!accept) return socket.send(JSON.stringify({ type: "decision", browserId: f.browserId, deviceId, accepted: false }));
      const box = await sealGrant({ phonePrivate: keys.privateKey, phonePub: keys.pub, browserPub: f.pub, grant: { secret, token, relayUrl: "wss://phone-relay.example" } });
      socket.send(JSON.stringify({ type: "decision", browserId: f.browserId, deviceId, accepted: true, ...box }));
      socket.seen = f;
    }
  });
  return { deviceId, keys, secret, token, socket };
}

const quick = { findMs: 20 };

test("the search lists the phones that answer, and a phone's name is trimmed", async () => {
  const lobby = fakeLobby();
  const phone = await fakePhone(lobby, { name: "x".repeat(100) });
  const found = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  assert.equal(found.length, 1);
  assert.equal(found[0].deviceId, phone.deviceId);
  assert.equal(found[0].name.length, 40);
  assert.equal(lobby.sockets.size, 1, "the page closed its lobby socket");
});

test("junk in the lobby never becomes a phone", async () => {
  const lobby = fakeLobby();
  const liar = new lobby.Socket("wss://relay.example/lobby");
  liar.addEventListener("message", () => {
    for (const bad of [{ type: "announce", deviceId: "short", pub: "ab" }, { type: "announce" }, [1, 2], "x"]) liar.send(typeof bad === "string" ? bad : JSON.stringify(bad));
  });
  const found = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  assert.deepEqual(found, []);
});

test("an accepted request gives the secret, the token and the PHONE'S relay, and the code matches what the phone sees", async () => {
  const lobby = fakeLobby();
  const phone = await fakePhone(lobby);
  const [found] = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  let shown = "";
  const result = await requestTrust({ relayUrl: "wss://relay.example", phone: found, WebSocketImpl: lobby.Socket, onCode: (c) => { shown = c; } });
  assert.equal(toHex(result.secret), toHex(phone.secret));
  assert.equal(toHex(result.token), toHex(phone.token));
  assert.equal(result.relayUrl, "wss://phone-relay.example");
  assert.match(shown, /^\d{4}$/);
  assert.equal(shown, await matchCode(phone.keys.pub, phone.socket.seen.pub), "same four digits on both screens");
  assert.equal(phone.socket.seen.name, computerName());
});

test("declining saves nothing and says so", async () => {
  const lobby = fakeLobby();
  await fakePhone(lobby, { accept: false });
  const [found] = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  await assert.rejects(requestTrust({ relayUrl: "wss://relay.example", phone: found, WebSocketImpl: lobby.Socket }), { kind: "declined" });
});

test("a phone that never answers times out with a clear reason", async () => {
  const lobby = fakeLobby();
  await fakePhone(lobby);
  const [found] = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  lobby.sockets.forEach((s) => { if (s.url.endsWith("/lobby")) s.handlers.message = []; });   // the phone goes quiet
  await assert.rejects(requestTrust({ relayUrl: "wss://relay.example", phone: found, WebSocketImpl: lobby.Socket, answerMs: 30 }), { kind: "no-answer" });
});

test("an answer sealed under another key (a man in the middle) is refused and nothing is returned", async () => {
  const lobby = fakeLobby();
  const phone = await fakePhone(lobby);
  const [found] = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  const attacker = await makeTrustKeys();
  phone.socket.handlers.message = [];
  phone.socket.addEventListener("message", async ({ data }) => {
    const f = JSON.parse(data);
    if (f.type !== "request") return;
    const box = await sealGrant({ phonePrivate: attacker.privateKey, phonePub: attacker.pub, browserPub: f.pub, grant: { secret: randomBytes(32), token: randomBytes(32), relayUrl: "wss://evil.example" } });
    phone.socket.send(JSON.stringify({ type: "decision", browserId: f.browserId, deviceId: phone.deviceId, accepted: true, ...box }));
  });
  await assert.rejects(requestTrust({ relayUrl: "wss://relay.example", phone: found, WebSocketImpl: lobby.Socket }), { kind: "bad-grant" });
});

test("a decision for another browser or from another phone is ignored", async () => {
  const lobby = fakeLobby();
  const phone = await fakePhone(lobby);
  const [found] = await findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: lobby.Socket, ...quick });
  phone.socket.handlers.message = [];                      // the real phone says nothing; only impostors speak
  const noise = new lobby.Socket("wss://relay.example/lobby");
  noise.addEventListener("message", () => {
    noise.send(JSON.stringify({ type: "decision", browserId: "00".repeat(16), deviceId: found.deviceId, accepted: true }));   // another browser
    noise.send(JSON.stringify({ type: "decision", browserId: "11".repeat(16), deviceId: "22".repeat(16), accepted: true }));   // another phone
  });
  await assert.rejects(requestTrust({ relayUrl: "wss://relay.example", phone: found, WebSocketImpl: lobby.Socket, answerMs: 80 }), { kind: "no-answer" });
});

test("a relay that cannot be reached is a clear failure, not a hang", async () => {
  class Dead { constructor() { this.h = {}; } addEventListener(t, f) { (this.h[t] ??= []).push(f); if (t === "error") queueMicrotask(f); } send() {} close() {} }
  await assert.rejects(findPhones({ relayUrl: "wss://relay.example", WebSocketImpl: Dead, ...quick }), { kind: "relay" });
});

test("the computer's name uses only the browser and the system", () => {
  assert.equal(computerName({ userAgent: "Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537" }), "Chrome on Windows");
  assert.equal(computerName({ userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X) Version/17 Safari/605" }), "Safari on Mac");
  assert.equal(computerName({}), "Browser on Computer");
});
