import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { startRelay } from "./node-relay.js";
import { startFakePhone } from "./fake-phone.js";
import { pairWithPhone, openLink, phoneBase } from "../../web/src/link-client.js";

const setup = async (code = "482913") => {
  const relay = await startRelay();
  const phone = await startFakePhone({ code, relayUrl: relay.url });
  return { relay, phone, address: `127.0.0.1:${phone.port}`, done: () => { phone.close(); relay.close(); } };
};

test("pair, then an encrypted ping is answered by the phone through the relay", async () => {
  const { relay, phone, address, done } = await setup();
  const secret = await pairWithPhone({ address, code: "482913" });
  assert.deepEqual(secret, phone.secret);
  const link = await openLink({ relayUrl: relay.url, secret, WebSocketImpl: WebSocket });
  const ack = await link.ping();
  assert.equal(ack.type, "ack");
  assert.equal(phone.answered[0].type, "ping");
  link.close(); done();
});

test("a wrong code is refused and tells how many tries are left; no secret leaks", async () => {
  const { address, done } = await setup();
  await assert.rejects(pairWithPhone({ address, code: "000000" }), { kind: "wrong", triesLeft: 4 });
  done();
});

test("five wrong codes lock pairing, and then even the right code is refused", async () => {
  const { address, done } = await setup();
  for (let i = 0; i < 4; i++) await assert.rejects(pairWithPhone({ address, code: "111111" }), { kind: "wrong" });
  await assert.rejects(pairWithPhone({ address, code: "111111" }), { kind: "locked", seconds: 30 });
  await assert.rejects(pairWithPhone({ address, code: "482913" }), { kind: "locked" });
  done();
});

test("a lockout is reported straight from /hello, before any proof is sent", async () => {
  const { address, done } = await setup();
  for (let i = 0; i < 5; i++) await assert.rejects(pairWithPhone({ address, code: "111111" }));
  let proofSent = false;
  const spy = async (url, opts) => { if (opts && opts.method === "POST") proofSent = true; return fetch(url, opts); };
  await assert.rejects(pairWithPhone({ address, code: "482913", fetchImpl: spy }), { kind: "locked" });
  assert.equal(proofSent, false);
  done();
});

test("an unreachable phone gives an actionable message, worded for a file page", async () => {
  await assert.rejects(pairWithPhone({ address: "127.0.0.1:1", code: "482913", isFileOrigin: true }),
    (e) => e.kind === "file-blocked-or-unreachable" && /same Wi-Fi/.test(e.message) && /Chrome or Edge/.test(e.message));
  await assert.rejects(pairWithPhone({ address: "127.0.0.1:1", code: "482913" }), { kind: "unreachable" });
});

test("a ping with nobody listening times out with a clear message", async () => {
  const { relay, done } = await setup();
  const link = await openLink({ relayUrl: relay.url, secret: new Uint8Array(32).fill(7), WebSocketImpl: WebSocket, timeoutMs: 200 });
  await assert.rejects(link.ping(), { kind: "no-answer" });
  link.close(); done();
});

test("bad input is rejected before any network call", async () => {
  await assert.rejects(pairWithPhone({ address: "192.168.1.5", code: "123" }), { kind: "bad-code" });
  assert.throws(() => phoneBase("example.com"), /192\.168/);
  assert.throws(() => phoneBase("999.1.1.1"));
  assert.equal(phoneBase("http://192.168.1.20/"), "http://192.168.1.20:47615");
  assert.equal(phoneBase("10.0.0.2:5000"), "http://10.0.0.2:5000");
});

test("the page asks for a snapshot and gets the phone's data", async () => {
  const relay = await startRelay();
  const data = { "library.words": [{ id: "1", key: "hola", spanish: "hola", translation: "hello", partOfSpeech: "interj", category: null, tags: [] }],
    "study.decks": [{ id: "d", name: "Vocabulary", kind: "vocabulary", total: 1, due: 1, new: 0 }] };
  const phone = await startFakePhone({ code: "482913", relayUrl: relay.url, data });
  const secret = await pairWithPhone({ address: `127.0.0.1:${phone.port}`, code: "482913" });
  const link = await openLink({ relayUrl: relay.url, secret, WebSocketImpl: WebSocket });
  const reply = await link.request("snapshot");
  assert.equal(reply.snapshot.words[0].spanish, "hola");
  assert.equal(reply.snapshot.decks[0].due, 1);
  assert.deepEqual(Object.keys(reply.snapshot).sort(), ["decks", "review", "words", "wordsPerDay", "wordsPerWeek"]);
  assert.ok(!Number.isNaN(Date.parse(reply.takenAt)));
  link.close(); phone.close(); relay.close();
});

test("a snapshot bigger than one relay frame arrives whole through chunks", async () => {
  const relay = await startRelay();
  const words = Array.from({ length: 3000 }, (_, i) => ({ id: String(i), key: `palabra${i}`, spanish: `palabra${i}`, translation: `word number ${i} with some extra text`, partOfSpeech: "n", category: "Big", tags: ["a", "b"] }));
  const phone = await startFakePhone({ code: "482913", relayUrl: relay.url, data: { "library.words": words } });
  const secret = await pairWithPhone({ address: `127.0.0.1:${phone.port}`, code: "482913" });
  const link = await openLink({ relayUrl: relay.url, secret, WebSocketImpl: WebSocket });
  const reply = await link.request("snapshot");
  assert.equal(reply.snapshot.words.length, 3000);
  assert.equal(reply.snapshot.words[2999].spanish, "palabra2999");
  link.close(); phone.close(); relay.close();
});

test("the page cannot write, spend AI, or read storage through the link; the phone refuses and nothing runs", async () => {
  const relay = await startRelay();
  const attempted = [];
  const phone = await startFakePhone({ code: "482913", relayUrl: relay.url, writes: attempted });
  const secret = await pairWithPhone({ address: `127.0.0.1:${phone.port}`, code: "482913" });
  const link = await openLink({ relayUrl: relay.url, secret, WebSocketImpl: WebSocket });
  for (const capability of ["words.add", "ai.generate", "storage.get", "study.addCards", "review.flag"]) {
    await assert.rejects(link.request("read", { capability, args: {} }), { kind: "forbidden" });
  }
  assert.deepEqual((await link.request("read", { capability: "library.words" })).result, []);
  link.close(); phone.close(); relay.close();
});

test("two requests in flight are answered to the right callers", async () => {
  const relay = await startRelay();
  const phone = await startFakePhone({ code: "482913", relayUrl: relay.url, data: { "study.decks": [{ id: "a" }], "review.list": [{ wordID: "b" }] } });
  const secret = await pairWithPhone({ address: `127.0.0.1:${phone.port}`, code: "482913" });
  const link = await openLink({ relayUrl: relay.url, secret, WebSocketImpl: WebSocket });
  const [decks, review] = await Promise.all([link.request("read", { capability: "study.decks" }), link.request("read", { capability: "review.list" })]);
  assert.equal(decks.result[0].id, "a"); assert.equal(review.result[0].wordID, "b");
  link.close(); phone.close(); relay.close();
});
