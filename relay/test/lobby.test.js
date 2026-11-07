import test from "node:test";
import assert from "node:assert/strict";
import { Lobby, lobbyName, LOBBY_MAX_PEERS, LOBBY_MAX_FRAME_CHARS, LOBBY_CLOSE } from "../src/lobby.js";

const peer = () => { const p = { got: [], closed: null, send: (d) => p.got.push(d), close: (c, r) => { p.closed = { c, r }; } }; return p; };
const frame = (type, extra = {}) => JSON.stringify({ type, ...extra });

test("a frame goes to everyone else in the lobby and never back to the sender", () => {
  const lobby = new Lobby();
  const [a, b, c] = [peer(), peer(), peer()];
  [a, b, c].forEach((p) => lobby.join(p));
  lobby.message(a, frame("announce", { name: "Hocine's iPhone" }));
  assert.deepEqual(a.got, []);
  assert.equal(b.got.length, 1);
  assert.equal(c.got.length, 1);
});

test("only known message types pass; anything else closes the sender", () => {
  for (const bad of ["not json", "[1]", "5", frame("snapshot"), frame("")]) {
    const lobby = new Lobby(); const a = peer(), b = peer(); lobby.join(a); lobby.join(b);
    lobby.message(a, bad);
    assert.equal(a.closed?.c, LOBBY_CLOSE.notJson.code, bad);
    assert.deepEqual(b.got, []);
  }
});

test("binary and oversized frames close the sender", () => {
  const lobby = new Lobby(); const a = peer(), b = peer(); lobby.join(a); lobby.join(b);
  lobby.message(a, new Uint8Array([1]));
  assert.equal(a.closed?.c, LOBBY_CLOSE.notText.code);
  const big = peer(); lobby.join(big);
  lobby.message(big, frame("hello", { pad: "x".repeat(LOBBY_MAX_FRAME_CHARS) }));
  assert.equal(big.closed?.c, LOBBY_CLOSE.tooBig.code);
  assert.deepEqual(b.got, []);
});

test("a flood is cut off", () => {
  let t = 0;
  const lobby = new Lobby(() => t); const a = peer(), b = peer(); lobby.join(a); lobby.join(b);
  for (let i = 0; i < 100 && !a.closed; i++) lobby.message(a, frame("hello"));
  assert.equal(a.closed?.c, LOBBY_CLOSE.tooFast.code);
  assert.ok(b.got.length <= 40);
});

test("the lobby has a size limit", () => {
  const lobby = new Lobby();
  for (let i = 0; i < LOBBY_MAX_PEERS; i++) assert.equal(lobby.join(peer()), true);
  const extra = peer();
  assert.equal(lobby.join(extra), false);
  assert.equal(extra.closed?.c, LOBBY_CLOSE.full.code);
});

test("a peer that left hears nothing more", () => {
  const lobby = new Lobby(); const a = peer(), b = peer(); lobby.join(a); lobby.join(b);
  lobby.leave(b);
  lobby.message(a, frame("hello"));
  assert.deepEqual(b.got, []);
  assert.equal(lobby.size, 1);
});

test("the lobby name is stable for one address and salt, differs otherwise, and does not contain the address", async () => {
  const one = await lobbyName("203.0.113.7", "salt");
  assert.equal(one, await lobbyName("203.0.113.7", "salt"));
  assert.notEqual(one, await lobbyName("203.0.113.8", "salt"));
  assert.notEqual(one, await lobbyName("203.0.113.7", "other"));
  assert.match(one, /^[0-9a-f]{32}$/);
  assert.ok(!one.includes("203"));
});
