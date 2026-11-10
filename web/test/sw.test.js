import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../src/sw.js", import.meta.url), "utf8");
const SHELL = ["/", "/app.js", "/app.css", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png"];
const ORIGIN = "https://x.test";
const pathOf = (input) => new URL(typeof input === "string" ? input : input.url, ORIGIN).pathname;

/** Runs the worker script against a fake `self`, an in-memory CacheStorage and a scriptable network. */
function boot({ version = "v1", seed = {} } = {}) {
  const listeners = {};
  const store = new Map(Object.entries(seed).map(([name, files]) => [name, new Map(Object.entries(files))]));
  const calls = { network: [], skipWaiting: 0, claim: 0 };
  const state = { network: async (request) => new Response(`net:${pathOf(request)}`, { status: 200 }) };
  const cacheApi = (files) => ({
    addAll: async (urls) => { for (const u of urls) files.set(pathOf(u), new Response(`cached:${pathOf(u)}`)); },
    put: async (key, response) => { files.set(pathOf(key), response); },
    match: async (key) => files.get(pathOf(key))?.clone(),
  });
  const caches = {
    open: async (name) => { if (!store.has(name)) store.set(name, new Map()); return cacheApi(store.get(name)); },
    keys: async () => [...store.keys()],
    delete: async (name) => store.delete(name),
    match: async (key) => { for (const files of store.values()) { const hit = files.get(pathOf(key)); if (hit) return hit.clone(); } return undefined; },
  };
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (type, fn) => { listeners[type] = fn; },
    skipWaiting: () => { calls.skipWaiting += 1; return Promise.resolve(); },
    clients: { claim: () => { calls.claim += 1; return Promise.resolve(); } },
  };
  const fetch = async (request) => { calls.network.push(pathOf(request)); return state.network(request); };
  const source = SOURCE.replace("__VERSION__", version).replace("__SHELL__", JSON.stringify(SHELL));
  vm.runInNewContext(source, { self, caches, fetch, URL, Response, Request, Promise, Error });

  const dispatch = async (type, event) => {
    let pending = null;
    let answered = false;
    listeners[type]({ ...event, waitUntil: (p) => { pending = p; }, respondWith: (p) => { answered = true; pending = p; } });
    return { answered, result: pending ? await pending : undefined };
  };
  const request = (path, extra = {}) => ({ url: ORIGIN + path, method: "GET", mode: "cors", ...extra });
  return { store, calls, state, dispatch, request };
}

test("install precaches the whole shell under palabra-shell-<version> and skips waiting", async () => {
  const sw = boot({ version: "abc123" });
  await sw.dispatch("install", {});
  assert.deepEqual([...sw.store.keys()], ["palabra-shell-abc123"]);
  assert.deepEqual([...sw.store.get("palabra-shell-abc123").keys()].sort(), [...SHELL].sort());
  assert.equal(sw.calls.skipWaiting, 1);
});

test("activate deletes older shell caches, keeps the current one and other names, and claims clients", async () => {
  const sw = boot({ version: "new", seed: { "palabra-shell-old": { "/": new Response("x") }, "palabra-shell-new": { "/": new Response("y") }, "something-else": {} } });
  await sw.dispatch("activate", {});
  assert.deepEqual([...sw.store.keys()].sort(), ["palabra-shell-new", "something-else"]);
  assert.equal(sw.calls.claim, 1);
});

test("fetch never answers /api/ requests, other methods or other origins", async () => {
  const sw = boot();
  for (const request of [
    sw.request("/api/m/abc/items?since=0"),
    sw.request("/api/pair/start", { method: "POST" }),
    sw.request("/app.js", { method: "POST" }),
    { url: "https://elsewhere.test/app.js", method: "GET", mode: "cors" },
  ]) {
    const { answered } = await sw.dispatch("fetch", { request });
    assert.equal(answered, false, request.url);
  }
  assert.deepEqual(sw.calls.network, []);
});

test("a cached asset is served without the network", async () => {
  const sw = boot();
  await sw.dispatch("install", {});
  const { answered, result } = await sw.dispatch("fetch", { request: sw.request("/app.js") });
  assert.equal(answered, true);
  assert.equal(await result.text(), "cached:/app.js");
  assert.deepEqual(sw.calls.network, []);
});

test("an uncached asset comes from the network; offline it fails instead of inventing a response", async () => {
  const sw = boot();
  const online = await sw.dispatch("fetch", { request: sw.request("/other.png") });
  assert.equal(await online.result.text(), "net:/other.png");
  sw.state.network = async () => { throw new TypeError("offline"); };
  const { result } = await sw.dispatch("fetch", { request: sw.request("/other2.png") }).catch((e) => ({ result: e }));
  assert.ok(result instanceof TypeError);
});

test("a navigation tries the network first and falls back to the cached shell when offline", async () => {
  const sw = boot();
  await sw.dispatch("install", {});
  const live = await sw.dispatch("fetch", { request: sw.request("/", { mode: "navigate" }) });
  assert.equal(await live.result.text(), "net:/", "network first");
  sw.state.network = async () => { throw new TypeError("offline"); };
  const offline = await sw.dispatch("fetch", { request: sw.request("/", { mode: "navigate" }) });
  assert.equal(await offline.result.text(), "net:/", "the page it fetched last is what the cache holds now");
  const other = await sw.dispatch("fetch", { request: sw.request("/some/where", { mode: "navigate" }) });
  assert.equal(await other.result.text(), "net:/", "any navigation falls back to the shell");
});

test("a successful navigation to / refreshes the cached shell, other pages and errors do not", async () => {
  const sw = boot();
  await sw.dispatch("install", {});
  sw.state.network = async (request) => new Response("fresh index", { status: pathOf(request) === "/" ? 200 : 200 });
  await sw.dispatch("fetch", { request: sw.request("/", { mode: "navigate" }) });
  assert.equal(await sw.store.get("palabra-shell-v1").get("/").clone().text(), "fresh index");
  sw.state.network = async () => new Response("oops", { status: 500 });
  await sw.dispatch("fetch", { request: sw.request("/", { mode: "navigate" }) });
  assert.equal(await sw.store.get("palabra-shell-v1").get("/").clone().text(), "fresh index", "a 500 never replaces the shell");
  sw.state.network = async () => new Response("elsewhere", { status: 200 });
  await sw.dispatch("fetch", { request: sw.request("/zzz", { mode: "navigate" }) });
  assert.equal(await sw.store.get("palabra-shell-v1").get("/").clone().text(), "fresh index", "only / is cached");
});

test("offline with nothing cached, a navigation fails (no invented page)", async () => {
  const sw = boot();
  sw.state.network = async () => { throw new TypeError("offline"); };
  const outcome = await sw.dispatch("fetch", { request: sw.request("/", { mode: "navigate" }) }).catch((e) => e);
  assert.ok(outcome instanceof Error);
});
