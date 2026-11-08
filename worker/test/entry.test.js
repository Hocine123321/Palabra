import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { makeFetch } from "../src/entry.js";
import { MirrorObject } from "../src/mirror-object.js";
import { nodeSqlite } from "../src/sql.js";
import { sha256Hex } from "../src/auth.js";
import { makeMemoryBackend } from "./support/memory-backend.js";

function setup() {
  const seen = [];
  const env = { ASSETS: { fetch: async (request) => (seen.push(new URL(request.url).pathname), new Response("asset", { status: 200 })) } };
  const factoryArgs = [];
  const fetch = makeFetch((e) => (factoryArgs.push(e), makeMemoryBackend()));
  return { env, seen, fetch, factoryArgs };
}
const req = (path, init) => new Request(`https://x.test${path}`, init);

test("/api and /api/... go to the router", async () => {
  const { env, seen, fetch, factoryArgs } = setup();
  for (const path of ["/api", "/api/", "/api/state-nope"]) {
    const res = await fetch(req(path), env);
    assert.equal(res.status, 404);
    assert.deepEqual(await res.json(), { error: "not_found" });
  }
  assert.deepEqual(seen, []);
  assert.ok(factoryArgs.every((e) => e === env), "the backend is built from env");
});

test("everything else is the web app", async () => {
  const { env, seen, fetch } = setup();
  for (const path of ["/", "/index.html", "/apix", "/api2/x", "/app/api/x"]) {
    const res = await fetch(req(path), env);
    assert.equal(await res.text(), "asset");
  }
  assert.deepEqual(seen, ["/", "/index.html", "/apix", "/api2/x", "/app/api/x"]);
});

test("the API reaches the backend end to end through the entry point", async () => {
  const { env, fetch } = setup();
  const res = await fetch(req("/api/pair/start", { method: "POST" }), env);
  assert.equal(res.status, 201);
});

test("a Mirror object writes nothing for an id that was never created", async () => {
  const db = new DatabaseSync(":memory:");
  const object = new MirrorObject(nodeSqlite(db));
  const tables = () => db.prepare("SELECT COUNT(*) AS n FROM sqlite_master").get().n;
  for (const call of [() => object.state("Bearer a.b"), () => object.putItems("Bearer a.b", []), () => object.listDevices("Bearer a.b")]) {
    assert.deepEqual(await call(), { ok: false, status: 401, error: "unauthorized" });
  }
  assert.equal(tables(), 0);
  // A refused create leaves nothing behind either.
  assert.equal(object.create({ deviceId: "d", ownerTokenHash: "nothex" }).status, 400);
  assert.equal(tables(), 0);
  const created = object.create({ deviceId: "phone", ownerTokenHash: await sha256Hex("tok") });
  assert.equal(created.ok, true);
  assert.ok(tables() > 0);
  assert.equal((await object.state("Bearer phone.tok")).ok, true);
  assert.equal(object.create({ deviceId: "x", ownerTokenHash: await sha256Hex("t") }).error, "already_created");
});
