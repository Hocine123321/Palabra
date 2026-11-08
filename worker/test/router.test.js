import { test } from "node:test";
import assert from "node:assert/strict";
import { handleApi } from "../src/router.js";
import { sha256Hex } from "../src/auth.js";
import { LIMITS } from "../src/limits.js";
import { makeMemoryBackend } from "./support/memory-backend.js";

async function call(backend, method, path, { body, auth, ip, headers = {}, raw } = {}) {
  const h = new Headers(headers);
  if (auth) h.set("Authorization", auth);
  if (ip) h.set("CF-Connecting-IP", ip);
  const init = { method, headers: h };
  if (raw !== undefined) init.body = raw;
  else if (body !== undefined) init.body = JSON.stringify(body);
  const res = await handleApi(new Request(`https://x.test${path}`, init), backend, { limits: backend.limits });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: res.status, json, res, text };
}

const PUB = "B".repeat(87);
const item = (n, sealed = "AAAA") => ({ id: `item${String(n).padStart(20, "0")}`, sealed });

async function newMirror(backend, ip = "9.9.9.9") {
  const r = await call(backend, "POST", "/api/mirrors", { body: { deviceId: "phone", ownerTokenHash: await sha256Hex("tok") }, ip });
  assert.equal(r.status, 201, r.text);
  return { mirrorId: r.json.mirrorId, owner: "Bearer phone.tok" };
}

test("mirror flow: create, add browser, put, read, revoke", async () => {
  const backend = makeMemoryBackend();
  const { mirrorId, owner } = await newMirror(backend);
  assert.equal(mirrorId.length, 22);
  const m = `/api/m/${mirrorId}`;
  const add = await call(backend, "POST", `${m}/devices`, { auth: owner, body: { deviceId: "b1", tokenHash: await sha256Hex("btok") } });
  assert.deepEqual([add.status, add.json], [201, {}]);
  const put = await call(backend, "PUT", `${m}/items`, { auth: owner, body: { items: [item(1), item(2), item(3)] } });
  assert.deepEqual([put.status, put.json], [200, { seq: 3 }]);
  const browser = "Bearer b1.btok";
  const list = await call(backend, "GET", `${m}/items?since=0`, { auth: browser });
  assert.equal(list.status, 200);
  assert.deepEqual(list.json.items.map((i) => i.seq), [1, 2, 3]);
  assert.deepEqual([list.json.seq, list.json.more], [3, false]);
  assert.deepEqual((await call(backend, "GET", `${m}/state`, { auth: browser })).json, { seq: 3 });
  const devices = await call(backend, "GET", `${m}/devices`, { auth: owner });
  assert.deepEqual(devices.json.devices.map((d) => d.deviceId).sort(), ["b1", "phone"]);
  assert.equal((await call(backend, "DELETE", `${m}/devices/b1`, { auth: owner })).status, 200);
  assert.equal((await call(backend, "GET", `${m}/items?since=0`, { auth: browser })).status, 401);
  assert.equal((await call(backend, "PUT", `${m}/items`, { auth: browser, body: { items: [item(9)] } })).status, 401);
});

test("items query: since and limit are strict numbers", async () => {
  const backend = makeMemoryBackend();
  const { mirrorId, owner } = await newMirror(backend);
  const m = `/api/m/${mirrorId}`;
  await call(backend, "PUT", `${m}/items`, { auth: owner, body: { items: [item(1), item(2), item(3)] } });
  assert.equal((await call(backend, "GET", `${m}/items`, { auth: owner })).json.items.length, 3);
  assert.equal((await call(backend, "GET", `${m}/items?since=1&limit=1`, { auth: owner })).json.more, true);
  for (const q of ["since=-1", "since=x", "since=1.5", "limit=abc", "since="]) {
    assert.equal((await call(backend, "GET", `${m}/items?${q}`, { auth: owner })).status, 400, q);
  }
});

test("pairing flow over HTTP, reply read once", async () => {
  const backend = makeMemoryBackend();
  const start = await call(backend, "POST", "/api/pair/start", {});
  assert.equal(start.status, 201);
  const { pairId, expiresAt } = start.json;
  assert.equal(typeof expiresAt, "number");
  const p = `/api/pair/${pairId}`;
  assert.deepEqual((await call(backend, "GET", p)).json, { state: "waiting" });
  assert.equal((await call(backend, "POST", `${p}/join`, { body: { phonePub: PUB } })).status, 200);
  assert.deepEqual((await call(backend, "GET", p)).json, { state: "joined", phonePub: PUB });
  const second = await call(backend, "POST", `${p}/join`, { body: { phonePub: PUB } });
  assert.deepEqual([second.status, second.json], [409, { error: "slot_taken" }]);
  assert.equal((await call(backend, "POST", `${p}/reply`, { body: { sealed: "SEALED" } })).status, 200);
  assert.deepEqual((await call(backend, "GET", p)).json, { state: "replied", sealed: "SEALED" });
  assert.deepEqual(await call(backend, "GET", p).then((r) => [r.status, r.json]), [404, { error: "not_found" }]);
  const other = (await call(backend, "POST", "/api/pair/start", {})).json.pairId;
  assert.equal((await call(backend, "POST", `/api/pair/${other}/cancel`)).status, 200);
  assert.deepEqual((await call(backend, "GET", `/api/pair/${other}`)).json, { state: "cancelled" });
});

test("a pairing slot past its lifetime is 410", async () => {
  const backend = makeMemoryBackend();
  const { pairId } = (await call(backend, "POST", "/api/pair/start", {})).json;
  backend.clock.advance(LIMITS.pairTtlSec + 1);
  const r = await call(backend, "GET", `/api/pair/${pairId}`);
  assert.deepEqual([r.status, r.json], [410, { error: "gone" }]);
});

test("routing errors: unknown 404, wrong method 405, bad JSON 400, bad ids 404", async () => {
  const backend = makeMemoryBackend();
  assert.deepEqual(await call(backend, "GET", "/api/nope").then((r) => [r.status, r.json]), [404, { error: "not_found" }]);
  const wrong = await call(backend, "GET", "/api/mirrors");
  assert.deepEqual([wrong.status, wrong.json], [405, { error: "method_not_allowed" }]);
  assert.equal((await call(backend, "POST", "/api/mirrors", { raw: "{not json" })).status, 400);
  assert.equal((await call(backend, "POST", "/api/mirrors", { raw: "[1,2]" })).status, 400);
  assert.equal((await call(backend, "POST", "/api/mirrors", { raw: "" })).status, 400);
  for (const path of ["/api/m/short/state", "/api/m/../state", "/api/m/%2e%2e/state", `/api/m/${"x".repeat(23)}/state`, "/api/pair/short", "/api/pair/a%2Fb/join"]) {
    assert.equal((await call(backend, "GET", path, { auth: "Bearer a.b" })).status, 404, path);
  }
  const { mirrorId, owner } = await newMirror(backend);
  assert.equal((await call(backend, "DELETE", `/api/m/${mirrorId}/devices/a%2Fb`, { auth: owner })).status, 404);
  assert.equal((await call(backend, "GET", `/api/m/${"y".repeat(22)}/state`, { auth: owner })).status, 404, "unknown mirror");
});

test("body cap: exactly 1 MiB passes the size check, one byte more is 413", async () => {
  const backend = makeMemoryBackend();
  const pad = (bytes) => {
    const base = '{"deviceId":"d","ownerTokenHash":"zz","pad":""}';
    return base.replace('"pad":""', `"pad":"${"A".repeat(bytes - base.length + 0)}"`);
  };
  const exact = pad(LIMITS.bodyBytes);
  assert.equal(new TextEncoder().encode(exact).length, LIMITS.bodyBytes);
  const ok = await call(backend, "POST", "/api/mirrors", { raw: exact });
  assert.equal(ok.status, 400, "validation, not size");
  const over = await call(backend, "POST", "/api/mirrors", { raw: exact + " " });
  assert.deepEqual([over.status, over.json], [413, { error: "too_large" }]);
  const multibyte = await call(backend, "POST", "/api/mirrors", { raw: "é".repeat(LIMITS.bodyBytes / 2 + 1) });
  assert.equal(multibyte.status, 413, "counted in bytes, not characters");
  const byHeader = await call(backend, "POST", "/api/mirrors", { raw: "{}", headers: { "content-length": String(LIMITS.bodyBytes + 1) } });
  assert.equal(byHeader.status, 413);
});

test("authorization: missing, huge or odd headers are 401 and never throw", async () => {
  const backend = makeMemoryBackend();
  const { mirrorId } = await newMirror(backend);
  const state = `/api/m/${mirrorId}/state`;
  assert.deepEqual(await call(backend, "GET", state).then((r) => [r.status, r.json]), [401, { error: "unauthorized" }]);
  for (const auth of ["x".repeat(10_000), "Bearer é.é", "Bearer " + "a".repeat(10_000), "Basic abc", "Bearer a.b.c", "Bearer phone.wrong"]) {
    assert.equal((await call(backend, "GET", state, { auth })).status, 401, auth.slice(0, 20));
  }
});

test("rate limit: the sixth mirror from one address in an hour is 429, another address is fine", async () => {
  const backend = makeMemoryBackend();
  for (let i = 0; i < 5; i++) {
    const r = await call(backend, "POST", "/api/mirrors", { ip: "1.1.1.1", body: { deviceId: `d${i}`, ownerTokenHash: await sha256Hex("t") } });
    assert.equal(r.status, 201);
  }
  const sixth = await call(backend, "POST", "/api/mirrors", { ip: "1.1.1.1", body: { deviceId: "d6", ownerTokenHash: await sha256Hex("t") } });
  assert.deepEqual([sixth.status, sixth.json], [429, { error: "rate_limited" }]);
  const retry = Number(sixth.res.headers.get("Retry-After"));
  assert.ok(retry >= 1 && retry <= 3600);
  const other = await call(backend, "POST", "/api/mirrors", { ip: "2.2.2.2", body: { deviceId: "d7", ownerTokenHash: await sha256Hex("t") } });
  assert.equal(other.status, 201);
});

test("pair start and poll are rate limited per address", async () => {
  const backend = makeMemoryBackend({ limits: {} });
  for (let i = 0; i < 10; i++) assert.equal((await call(backend, "POST", "/api/pair/start", { ip: "3.3.3.3" })).status, 201);
  assert.equal((await call(backend, "POST", "/api/pair/start", { ip: "3.3.3.3" })).status, 429);
  const { pairId } = (await call(backend, "POST", "/api/pair/start", { ip: "4.4.4.4" })).json;
  for (let i = 0; i < 300; i++) assert.equal((await call(backend, "GET", `/api/pair/${pairId}`, { ip: "4.4.4.4" })).status, 200);
  assert.equal((await call(backend, "GET", `/api/pair/${pairId}`, { ip: "4.4.4.4" })).status, 429);
});

test("store rate limits come through as 429 with Retry-After", async () => {
  const backend = makeMemoryBackend({ limits: { rates: { ...LIMITS.rates, itemsPut: [1, 60] } } });
  const { mirrorId, owner } = await newMirror(backend);
  const m = `/api/m/${mirrorId}`;
  assert.equal((await call(backend, "PUT", `${m}/items`, { auth: owner, body: { items: [item(1)] } })).status, 200);
  const limited = await call(backend, "PUT", `${m}/items`, { auth: owner, body: { items: [item(2)] } });
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.res.headers.get("Retry-After")) >= 1);
});

test("every response is same-origin JSON with no-store and no CORS headers", async () => {
  const backend = makeMemoryBackend();
  const { mirrorId, owner } = await newMirror(backend);
  const responses = [
    await call(backend, "GET", "/api/nope"),
    await call(backend, "POST", "/api/pair/start"),
    await call(backend, "GET", `/api/m/${mirrorId}/state`, { auth: owner }),
    await call(backend, "GET", `/api/m/${mirrorId}/state`),
    await call(backend, "OPTIONS", "/api/mirrors"),
  ];
  for (const r of responses) {
    assert.equal(r.res.headers.get("Cache-Control"), "no-store");
    assert.match(r.res.headers.get("Content-Type"), /^application\/json/);
    for (const [name] of r.res.headers) assert.ok(!name.toLowerCase().startsWith("access-control-"), name);
  }
});

test("a store that throws becomes 500 without echoing the message", async () => {
  const backend = makeMemoryBackend();
  backend.gate.startPairing = () => { throw new Error("secret detail"); };
  const r = await call(backend, "POST", "/api/pair/start");
  assert.deepEqual([r.status, r.json], [500, { error: "internal" }]);
  assert.ok(!r.text.includes("secret"));
});

test("per-address limits treat a whole IPv6 /64 as one address", async () => {
  const backend = makeMemoryBackend();
  for (let i = 0; i < 10; i++) {
    const r = await call(backend, "POST", "/api/pair/start", { ip: `2001:db8:1:2:${i}::${i + 1}` });
    assert.equal(r.status, 201);
  }
  assert.equal((await call(backend, "POST", "/api/pair/start", { ip: "2001:db8:1:2:ffff:1:2:3" })).status, 429);
  assert.equal((await call(backend, "POST", "/api/pair/start", { ip: "2001:db8:1:3::1" })).status, 201, "another /64 is separate");
});

test("odd method names are 405 or 404, never a crash or a non-Response", async () => {
  const backend = makeMemoryBackend();
  for (const method of ["valueOf", "hasOwnProperty", "toString", "constructor"]) {
    const res = await handleApi({ method, url: "https://x.test/api/mirrors", headers: new Headers() }, backend);
    assert.ok(res instanceof Response, method);
    assert.equal(res.status, 405, method);
  }
});

test("the body cap stops reading a stream that has no Content-Length", async () => {
  const backend = makeMemoryBackend();
  let pulled = 0;
  const chunk = new Uint8Array(65_536).fill(65);
  const body = new ReadableStream({
    pull(controller) {
      pulled += chunk.length;
      controller.enqueue(chunk);
      if (pulled > 40 * 1024 * 1024) controller.close();
    },
  });
  const res = await handleApi(new Request("https://x.test/api/mirrors", { method: "POST", body, duplex: "half" }), backend);
  assert.equal(res.status, 413);
  assert.ok(pulled < 4 * 1024 * 1024, `read ${pulled} bytes`);
});

test("an unauthenticated PUT is refused before its body is read", async () => {
  const backend = makeMemoryBackend();
  const { mirrorId } = await newMirror(backend);
  const body = new ReadableStream({ pull(c) { c.enqueue(new Uint8Array(10)); c.close(); } });
  const request = new Request(`https://x.test/api/m/${mirrorId}/items`, { method: "PUT", body, duplex: "half" });
  const res = await handleApi(request, backend);
  assert.equal(res.status, 401);
  assert.equal(request.bodyUsed, false);
  assert.equal(request.body.locked, false);
});

test("a global daily cap on new mirrors holds across addresses", async () => {
  const backend = makeMemoryBackend({ limits: { rates: { ...LIMITS.rates, mirrorsDay: [3, 86400] } } });
  for (let i = 0; i < 3; i++) {
    const r = await call(backend, "POST", "/api/mirrors", { ip: `10.0.0.${i}`, body: { deviceId: `d${i}`, ownerTokenHash: await sha256Hex("t") } });
    assert.equal(r.status, 201);
  }
  const r = await call(backend, "POST", "/api/mirrors", { ip: "10.0.0.99", body: { deviceId: "dx", ownerTokenHash: await sha256Hex("t") } });
  assert.equal(r.status, 429);
});
