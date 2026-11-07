// Two real WebSocket clients through the relay, using the real crypto: the encrypted ping the phase is about.
import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { startRelay } from "./node-relay.js";
import { Session, roomId, randomBytes } from "../../web/src/link-crypto.js";

const connect = (url) => new Promise((res, rej) => {
  const ws = new WebSocket(url);
  ws.binaryType = "nodebuffer";
  const queue = [], waiters = [];
  ws.on("message", (d, bin) => { const v = { d: new Uint8Array(d), bin }; const w = waiters.shift(); w ? w(v) : queue.push(v); });
  ws.next = () => new Promise((r) => { const v = queue.shift(); v ? r(v) : waiters.push(r); });
  ws.closed = new Promise((r) => ws.on("close", (code) => r(code)));
  ws.on("open", () => res(ws));
  ws.on("error", rej);
});

test("encrypted ping and ack through the relay; the relay only sees opaque bytes", async () => {
  const relay = await startRelay();
  const secret = randomBytes(32);
  const room = await roomId(secret);
  const [appWs, webWs] = [await connect(`${relay.url}/r/${room}`), await connect(`${relay.url}/r/${room}`)];
  const app = await Session.open(secret, "app"), web = await Session.open(secret, "web");

  const sent = await web.seal({ id: "1", type: "ping", version: 1, payload: { word: "hola" } });
  webWs.send(sent);
  const atApp = await appWs.next();
  assert.deepEqual(atApp.d, sent);                                     // relay forwarded the bytes untouched
  assert.ok(!Buffer.from(atApp.d).toString("latin1").includes("hola")); // and they are not plaintext
  const msg = await app.open(atApp.d);
  assert.equal(msg.type, "ping");

  appWs.send(await app.seal({ id: "1", type: "ack", version: 1, payload: {} }));
  assert.equal((await web.open((await webWs.next()).d)).type, "ack");
  appWs.close(); webWs.close(); relay.close();
});

test("a different room never receives the frame; a third end is refused", async () => {
  const relay = await startRelay();
  const s1 = randomBytes(32), s2 = randomBytes(32);
  const a = await connect(`${relay.url}/r/${await roomId(s1)}`);
  const b = await connect(`${relay.url}/r/${await roomId(s1)}`);
  const other = await connect(`${relay.url}/r/${await roomId(s2)}`);
  const third = await connect(`${relay.url}/r/${await roomId(s1)}`);
  assert.equal(await third.closed, 4001);
  a.send(new Uint8Array([9, 9, 9]));
  assert.deepEqual((await b.next()).d, new Uint8Array([9, 9, 9]));
  const raced = await Promise.race([other.next(), new Promise((r) => setTimeout(() => r("nothing"), 150))]);
  assert.equal(raced, "nothing");
  [a, b, other].forEach((w) => w.close()); relay.close();
});

test("a bad room path is refused", async () => {
  const relay = await startRelay();
  await assert.rejects(connect(`${relay.url}/r/not-a-room`));
  relay.close();
});
