import { test } from "node:test";
import assert from "node:assert/strict";
import { handleApi } from "../../worker/src/router.js";
import { makeMemoryBackend } from "../../worker/test/support/memory-backend.js";
import { ApiError, OfflineError, createApi } from "../src/api.js";
import { createPairing, credentialsFromWrap } from "../src/pairing.js";
import { qrTree } from "../src/qr.js";
import { decode, encode } from "../src/b64url.js";
import { CryptoFailure, deriveKPair, generatePairKeys, matchCode } from "../src/crypto.js";

const ORIGIN = "https://x.test";
const utf8 = (s) => new TextEncoder().encode(s);

function harness() {
  const backend = makeMemoryBackend();
  const fetchImpl = (url, init) => handleApi(new Request(url, init), backend, { limits: backend.limits });
  let nowMs = 5_000_000;
  const now = () => nowMs;
  const api = createApi(ORIGIN, fetchImpl);
  const pairing = createPairing({ api, origin: ORIGIN, now });
  return { backend, fetchImpl, api, pairing, now, advance: (ms) => (nowMs += ms) };
}

function parseLink(link) {
  const url = new URL(link);
  const params = new URLSearchParams(url.hash.slice(1));
  return { origin: url.origin, pairId: params.get("p"), browserPub: decode(params.get("k")), nonce: decode(params.get("n")) };
}

/** A JavaScript stand-in for the phone: joins and replies the way plan 2's Swift phone does. */
async function fakePhone(fetchImpl, link, { wrapKeyOverride, deviceKey } = {}) {
  const { pairId, browserPub, nonce } = parseLink(link);
  const keys = await generatePairKeys();
  const join = await fetchImpl(`${ORIGIN}/api/pair/${pairId}/join`, { method: "POST", body: JSON.stringify({ phonePub: encode(keys.publicRaw) }) });
  const code = await matchCode(browserPub, keys.publicRaw, nonce);
  const secrets = { mirrorId: "MIRRORID", deviceId: "DEVICEID", deviceToken: "TOKEN", dataKey: encode(new Uint8Array(32).fill(7)), ...(deviceKey ? { deviceKey: encode(deviceKey) } : {}) };
  async function reply() {
    const kPair = wrapKeyOverride ?? (await deriveKPair(keys.privateKey, browserPub, nonce));
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: utf8(`palabra-mirror-wrap-v1|${pairId}`), tagLength: 128 }, kPair, utf8(JSON.stringify({ v: 1, ...secrets }))));
    const sealed = new Uint8Array([...iv, ...ct]);
    return fetchImpl(`${ORIGIN}/api/pair/${pairId}/reply`, { method: "POST", body: JSON.stringify({ sealed: encode(sealed) }) });
  }
  return { joinStatus: join.status, code, reply, secrets };
}

test("start returns a link that parses back, polling walks waiting -> joined -> replied, accept returns the secrets", async () => {
  const { fetchImpl, pairing } = harness();
  const { link, pairId } = await pairing.start();
  assert.match(link, /^https:\/\/x\.test\/#p=[A-Za-z0-9_-]{22}&k=[A-Za-z0-9_-]{87}&n=[A-Za-z0-9_-]{22}$/);
  const parsed = parseLink(link);
  assert.equal(parsed.pairId, pairId);
  assert.equal(parsed.browserPub.length, 65);
  assert.equal(parsed.nonce.length, 16);
  assert.deepEqual(await pairing.poll(), { state: "waiting" });

  const phone = await fakePhone(fetchImpl, link);
  assert.equal(phone.joinStatus, 200);
  assert.deepEqual(await pairing.poll(), { state: "joined", code: phone.code });
  assert.match(phone.code, /^\d{4}$/);

  await phone.reply();
  const replied = await pairing.poll();
  assert.equal(replied.state, "replied");
  assert.equal(replied.code, phone.code);
  const got = await pairing.accept();
  assert.deepEqual([got.mirrorId, got.deviceId, got.deviceToken], ["MIRRORID", "DEVICEID", "TOKEN"]);
  assert.deepEqual(got.dataKey, new Uint8Array(32).fill(7));
  await assert.rejects(pairing.accept(), /already|not ready|replied/i, "a second accept is refused");
});

test("accept before the phone replied throws", async () => {
  const { fetchImpl, pairing } = harness();
  const { link } = await pairing.start();
  await assert.rejects(pairing.accept());
  await fakePhone(fetchImpl, link);
  await pairing.poll();
  await assert.rejects(pairing.accept());
});

test("someone who joined first shows a different code and the real phone's join is refused", async () => {
  const { fetchImpl, pairing } = harness();
  const { link } = await pairing.start();
  const attacker = await fakePhone(fetchImpl, link);
  const real = await fakePhone(fetchImpl, link);
  assert.equal(attacker.joinStatus, 200);
  assert.equal(real.joinStatus, 409);
  const shown = await pairing.poll();
  assert.equal(shown.code, attacker.code);
  assert.notEqual(shown.code, real.code, "the person sees a code the phone does not show");
});

test("a reply sealed under a different key is rejected and releases nothing", async () => {
  const { fetchImpl, pairing } = harness();
  const { link } = await pairing.start();
  const stranger = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt"]);
  const phone = await fakePhone(fetchImpl, link, { wrapKeyOverride: stranger });
  await pairing.poll();
  await phone.reply();
  await pairing.poll();
  await assert.rejects(pairing.accept(), CryptoFailure);
});

test("cancel is reported, and the slot expiring locally needs no request", async () => {
  const a = harness();
  await a.pairing.start();
  await a.pairing.cancel();
  assert.deepEqual(await a.pairing.poll(), { state: "cancelled" });

  const b = harness();
  const { expiresAt } = await b.pairing.start();
  let calls = 0;
  const counting = createPairing({ api: { ...b.api, pairStart: b.api.pairStart, pairGet: async () => { calls++; return {}; } }, origin: ORIGIN, now: b.now });
  await counting.start();
  b.advance(10 * 60 * 1000);
  assert.deepEqual(await counting.poll(), { state: "expired" });
  assert.equal(calls, 0);
  assert.ok(expiresAt > b.now() - 10 * 60 * 1000);
});

test("a slot the server already dropped is reported as expired", async () => {
  const { backend, pairing } = harness();
  await pairing.start();
  backend.clock.advance(500);
  assert.deepEqual(await pairing.poll(), { state: "expired" });
});

test("ApiError carries status and code; OfflineError when fetch rejects", async () => {
  const limited = createApi(ORIGIN, async () => new Response(JSON.stringify({ error: "rate_limited" }), { status: 429 }));
  await assert.rejects(limited.pairStart(), (e) => e instanceof ApiError && e.status === 429 && e.code === "rate_limited");
  const odd = createApi(ORIGIN, async () => new Response("<html>", { status: 502 }));
  await assert.rejects(odd.pairStart(), (e) => e instanceof ApiError && e.status === 502 && e.code === "unknown");
  const down = createApi(ORIGIN, async () => { throw new TypeError("Failed to fetch"); });
  await assert.rejects(down.pairStart(), OfflineError);
});

test("items and state send the bearer and the paging parameters", async () => {
  const seen = [];
  const api = createApi(ORIGIN, async (url, init) => (seen.push([url, init.headers.Authorization ?? init.headers.authorization]), new Response(JSON.stringify({ items: [], seq: 0, more: false }), { status: 200 })));
  await api.items("MIR", "dev.tok", 5, 50);
  await api.state("MIR", "dev.tok");
  assert.deepEqual(seen, [
    [`${ORIGIN}/api/m/MIR/items?since=5&limit=50`, "Bearer dev.tok"],
    [`${ORIGIN}/api/m/MIR/state`, "Bearer dev.tok"],
  ]);
});

test("qrTree is an svg with a path and no inline styles", () => {
  const tree = qrTree("https://x.test/#p=1");
  assert.equal(tree.tag, "svg");
  const walk = (node, fn) => { fn(node); for (const c of node.children ?? []) if (typeof c !== "string") walk(c, fn); };
  const tags = [];
  walk(tree, (n) => { tags.push(n.tag); assert.ok(!("style" in n.attrs), "no style attribute"); });
  assert.ok(tags.includes("path"));
  const path = (function find(n) { return n.tag === "path" ? n : n.children.filter((c) => typeof c !== "string").map(find).find(Boolean); })(tree);
  assert.ok(path.attrs.d.length > 10);
});

test("the wrap's device key becomes a non-extractable decrypt-only key, and an older phone's wrap gives null", async () => {
  for (const withKey of [true, false]) {
    const { fetchImpl, pairing } = harness();
    const { link } = await pairing.start();
    const phone = await fakePhone(fetchImpl, link, { deviceKey: withKey ? new Uint8Array(32).fill(4) : undefined });
    await pairing.poll();
    await phone.reply();
    await pairing.poll();
    const creds = await credentialsFromWrap(await pairing.accept());
    assert.deepEqual([creds.mirrorId, creds.deviceId, creds.deviceToken, creds.epoch], ["MIRRORID", "DEVICEID", "TOKEN", 0]);
    assert.equal(creds.keys.aes.extractable, false);
    if (withKey) {
      assert.equal(creds.deviceKey.extractable, false);
      assert.deepEqual(creds.deviceKey.usages, ["decrypt"]);
    } else {
      assert.equal(creds.deviceKey, null);
    }
  }
});
