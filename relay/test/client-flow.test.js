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

test("an unreachable phone gives an actionable message, worded for a file page", async () => {
  await assert.rejects(pairWithPhone({ address: "127.0.0.1:1", code: "482913", isFileOrigin: true }),
    (e) => e.kind === "file-blocked-or-unreachable" && /same Wi-Fi/.test(e.message) && /Chrome or Edge/.test(e.message));
  await assert.rejects(pairWithPhone({ address: "127.0.0.1:1", code: "482913" }), { kind: "unreachable" });
});

test("a ping with nobody listening times out with a clear message", async () => {
  const { relay, done } = await setup();
  const link = await openLink({ relayUrl: relay.url, secret: new Uint8Array(32).fill(7), WebSocketImpl: WebSocket });
  await assert.rejects(link.ping(200), { kind: "no-answer" });
  link.close(); done();
});

test("bad input is rejected before any network call", async () => {
  await assert.rejects(pairWithPhone({ address: "192.168.1.5", code: "123" }), { kind: "bad-code" });
  assert.throws(() => phoneBase("example.com"), /192\.168/);
  assert.throws(() => phoneBase("999.1.1.1"));
  assert.equal(phoneBase("http://192.168.1.20/"), "http://192.168.1.20:47615");
  assert.equal(phoneBase("10.0.0.2:5000"), "http://10.0.0.2:5000");
});
