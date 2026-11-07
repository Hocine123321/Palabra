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

// The failure seen on a real phone: after pairing, the page showed "away" with no data. Either end can rebuild its
// session at any time (the page reloads or retries; the phone comes back to the foreground). Counters then restart
// at 0, and the other end used to drop every frame as "replayed", with no error anywhere.
test("a page that reloads, and a phone that rebuilds its session, both still get answered over real sockets", async () => {
  const relay = await startRelay();
  const secret = randomBytes(32);
  const room = await roomId(secret);
  const answerWith = async (phoneWs, phone, webSocket, session, id) => {
    webSocket.send(await session.seal({ id, type: "snapshot", version: 1, payload: null }));
    const request = await phone.open((await phoneWs.next()).d);
    assert.equal(request.id, id);
    phoneWs.send(await phone.seal({ id, type: "ack", version: 1, payload: { snapshot: { words: [] }, takenAt: "t" } }));
    return (await session.open((await webSocket.next()).d)).payload.snapshot;
  };

  let phoneWs = await connect(`${relay.url}/r/${room}`);
  let phone = await Session.open(secret, "app");
  let webWs = await connect(`${relay.url}/r/${room}`);
  let web = await Session.open(secret, "web");
  for (const id of ["a", "b", "c"]) assert.deepEqual(await answerWith(phoneWs, phone, webWs, web, id), { words: [] });   // counters 0..2 used

  webWs.close(); await webWs.closed;                                        // the page reloads: new socket, new session, counter 0 again
  await new Promise((r) => setTimeout(r, 100));                              // the relay frees the room slot
  webWs = await connect(`${relay.url}/r/${room}`);
  web = await Session.open(secret, "web");
  assert.deepEqual(await answerWith(phoneWs, phone, webWs, web, "d"), { words: [] });

  phoneWs.close(); await phoneWs.closed;                                     // the phone leaves and returns: new socket, new session
  await new Promise((r) => setTimeout(r, 100));
  phoneWs = await connect(`${relay.url}/r/${room}`);
  phone = await Session.open(secret, "app");
  assert.deepEqual(await answerWith(phoneWs, phone, webWs, web, "e"), { words: [] });

  phoneWs.close(); webWs.close(); relay.close();
});
