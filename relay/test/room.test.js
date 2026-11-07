import test from "node:test";
import assert from "node:assert/strict";
import { Room, Bucket, CLOSE, MAX_FRAME_BYTES } from "../src/room.js";

const peer = () => {
  const p = { got: [], closed: null, send: (d) => p.got.push(d), close: (c, r) => (p.closed = { c, r }) };
  return p;
};

test("forwards a frame to the other end only", () => {
  const room = new Room();
  const a = peer(), b = peer();
  room.join(a); room.join(b);
  room.message(a, new Uint8Array([1, 2, 3]));
  assert.equal(b.got.length, 1);
  assert.equal(a.got.length, 0);
});

test("a third end is refused", () => {
  const room = new Room();
  room.join(peer()); room.join(peer());
  const c = peer();
  assert.equal(room.join(c), false);
  assert.equal(c.closed.c, CLOSE.roomFull.code);
});

test("text frames and oversized frames close the sender and are not forwarded", () => {
  const room = new Room();
  const a = peer(), b = peer();
  room.join(a); room.join(b);
  room.message(a, "hello");
  assert.equal(a.closed.c, CLOSE.notBinary.code);
  const c = peer(), d = peer();
  const r2 = new Room(); r2.join(c); r2.join(d);
  r2.message(c, new Uint8Array(MAX_FRAME_BYTES + 1));
  assert.equal(c.closed.c, CLOSE.tooBig.code);
  assert.equal(b.got.length + d.got.length, 0);
});

test("token bucket allows a burst, then refuses, then refills", () => {
  let t = 0;
  const bucket = new Bucket(10, () => t);
  let ok = 0;
  for (let i = 0; i < 30; i++) if (bucket.take()) ok++;
  assert.equal(ok, 20);
  t += 1000;
  assert.equal(bucket.take(), true);
});

test("a flooding sender is closed", () => {
  let t = 0;
  const room = new Room(() => t);
  const a = peer(), b = peer();
  room.join(a); room.join(b);
  for (let i = 0; i < 200; i++) room.message(a, new Uint8Array(1));
  assert.equal(a.closed.c, CLOSE.tooFast.code);
});

test("leaving frees the slot", () => {
  const room = new Room();
  const a = peer(), b = peer();
  room.join(a); room.join(b); room.leave(a);
  assert.equal(room.join(peer()), true);
});

// ---- roles, replacement and presence (the permanent fix for "waiting for the phone / browser") ----

const texts = (p) => p.got.filter((g) => typeof g === "string");

test("REPRO FIXED: a phone socket that died unnoticed cannot lock out its own reconnect", () => {
  const room = new Room();
  const ghost = peer(), browser = peer(), again = peer();
  room.join(ghost, "app"); room.join(browser, "web");
  assert.equal(room.join(again, "app"), true);
  assert.equal(ghost.closed.c, CLOSE.replaced.code, "the old socket is told it was replaced");
  assert.equal(again.closed, null);
  room.message(again, new Uint8Array([7]));
  assert.equal(browser.got.filter((g) => typeof g !== "string").length, 1, "frames flow to the browser again");
  room.message(ghost, new Uint8Array([9]));
  assert.equal(browser.got.filter((g) => typeof g !== "string").length, 1, "the replaced socket is no longer heard");
});

test("a browser that reconnects replaces the old browser, not the phone", () => {
  const room = new Room();
  const phone = peer(), web1 = peer(), web2 = peer();
  room.join(phone, "app"); room.join(web1, "web"); room.join(web2, "web");
  assert.equal(web1.closed.c, CLOSE.replaced.code);
  assert.equal(phone.closed, null);
  assert.equal(room.size, 2);
});

test("each end learns whether the other is there", () => {
  const room = new Room();
  const phone = peer(), browser = peer();
  room.join(phone, "app");
  assert.deepEqual(texts(phone), ["peer:gone"], "alone in the room");
  room.join(browser, "web");
  assert.deepEqual(texts(browser), ["peer:here"], "the newcomer is told the phone is already there");
  assert.deepEqual(texts(phone), ["peer:gone", "peer:here"], "the phone is told the browser arrived");
  room.leave(browser);
  assert.deepEqual(texts(phone), ["peer:gone", "peer:here", "peer:gone"]);
});

test("a replaced end does not announce 'gone' for its successor's seat", () => {
  const room = new Room();
  const phone = peer(), web1 = peer(), web2 = peer();
  room.join(phone, "app"); room.join(web1, "web"); room.join(web2, "web");
  room.leave(web1);                                   // the closed old socket finally reports
  assert.equal(texts(phone).at(-1), "peer:here", "the browser seat is still taken by web2");
  assert.equal(room.size, 2);
});

test("peers cannot forge presence notices: text from a peer closes it and is not forwarded", () => {
  const room = new Room();
  const phone = peer(), browser = peer();
  room.join(phone, "app"); room.join(browser, "web");
  const before = texts(browser).length;
  room.message(phone, "peer:gone");
  assert.equal(phone.closed.c, CLOSE.notBinary.code);
  assert.equal(texts(browser).length, before);
});

test("an unknown role is refused; no role keeps the old two-seat behaviour", () => {
  const room = new Room();
  const bad = peer();
  assert.equal(room.join(bad, "admin"), false);
  const a = peer(), b = peer(), c = peer();
  assert.equal(room.join(a), true); assert.equal(room.join(b), true);
  assert.equal(room.join(c), false);
  assert.equal(c.closed.c, CLOSE.roomFull.code);
});
