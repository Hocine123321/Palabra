import { test } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { makeFetch } from "../src/entry.js";
import { makeMemoryBackend } from "./support/memory-backend.js";

const SMOKE = fileURLToPath(new URL("../scripts/smoke.mjs", import.meta.url));
const CSP = "default-src 'none'; frame-ancestors 'none'";

/** A local stand-in for the deployed Worker: the real entry point, in-memory stores, stub assets. */
function serve({ csp = CSP, cors = false } = {}) {
  const backend = makeMemoryBackend();
  const env = { ASSETS: { fetch: async () => new Response("<!doctype html>", { headers: { "content-security-policy": csp, "content-type": "text/html" } }) } };
  const fetch = makeFetch(() => backend);
  const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const init = { method: req.method, headers: req.headers };
    if (body && req.method !== "GET" && req.method !== "HEAD") init.body = body;
    const response = await fetch(new Request(`http://localhost${req.url}`, init), env);
    const headers = Object.fromEntries(response.headers);
    if (cors) headers["access-control-allow-origin"] = "*";
    res.writeHead(response.status, headers);
    res.end(Buffer.from(await response.arrayBuffer()));
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` })));
}

function runSmoke(url) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [SMOKE, url], { stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("close", (code) => resolve({ code, out }));
  });
}

test("smoke script passes against a correct Worker and prints one line per check", async () => {
  const { server, url } = await serve();
  try {
    const { code, out } = await runSmoke(url);
    assert.equal(code, 0, out);
    assert.ok(out.split("\n").filter((l) => l.startsWith("ok")).length >= 8, out);
  } finally {
    server.close();
  }
});

test("smoke script fails when the CSP is missing frame-ancestors", async () => {
  const { server, url } = await serve({ csp: "default-src 'none'" });
  try {
    const { code, out } = await runSmoke(url);
    assert.notEqual(code, 0);
    assert.match(out, /frame-ancestors/);
  } finally {
    server.close();
  }
});

test("smoke script fails when a response carries a CORS header", async () => {
  const { server, url } = await serve({ cors: true });
  try {
    const { code, out } = await runSmoke(url);
    assert.notEqual(code, 0);
    assert.match(out, /access-control/i);
  } finally {
    server.close();
  }
});

test("smoke script fails with a usage message when no URL is given", async () => {
  const { code, out } = await runSmoke("");
  assert.notEqual(code, 0);
  assert.match(out, /usage/i);
});
