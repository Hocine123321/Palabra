// Real sockets through the test relay: devices behind one address find each other, others never hear them.
import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { startRelay } from "./node-relay.js";

const join = (url, ip) => new Promise((res, rej) => {
  const ws = new WebSocket(url, { headers: { "x-test-ip": ip } });
  const queue = [], waiters = [];
  ws.on("message", (d) => { const v = JSON.parse(d.toString()); const w = waiters.shift(); w ? w(v) : queue.push(v); });
  ws.next = () => new Promise((r) => { const v = queue.shift(); v ? r(v) : waiters.push(r); });
  ws.quiet = (ms = 150) => Promise.race([ws.next().then(() => "heard"), new Promise((r) => setTimeout(() => r("quiet"), ms))]);
  ws.on("open", () => res(ws));
  ws.on("error", rej);
});

test("a phone and a browser behind the same address find each other; a device elsewhere hears nothing", async () => {
  const relay = await startRelay();
  const phone = await join(`${relay.url}/lobby`, "203.0.113.7");
  const browser = await join(`${relay.url}/lobby`, "203.0.113.7");
  const stranger = await join(`${relay.url}/lobby`, "198.51.100.9");

  phone.send(JSON.stringify({ type: "announce", deviceId: "d1", name: "Hocine's iPhone", pub: "abc" }));
  const heard = await browser.next();
  assert.equal(heard.type, "announce");
  assert.equal(heard.name, "Hocine's iPhone");
  assert.equal(await stranger.quiet(), "quiet", "another network never sees the phone");

  browser.send(JSON.stringify({ type: "request", to: "d1", browserId: "b1", name: "Laptop", pub: "xyz" }));
  assert.equal((await phone.next()).type, "request");
  assert.equal(await stranger.quiet(), "quiet");

  [phone, browser, stranger].forEach((w) => w.close()); relay.close();
});

test("a lobby socket that sends garbage is closed and the others are undisturbed", async () => {
  const relay = await startRelay();
  const a = await join(`${relay.url}/lobby`, "203.0.113.7");
  const b = await join(`${relay.url}/lobby`, "203.0.113.7");
  const closed = new Promise((r) => a.on("close", (code) => r(code)));
  a.send("this is not json");
  assert.equal(await closed, 4015);
  assert.equal(await b.quiet(), "quiet");
  b.close(); relay.close();
});
