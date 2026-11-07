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
