// A real-browser check of the whole page against the Worker's real router (in memory), with a JavaScript "phone".
// NOT run by CI: it needs Playwright and a Chromium (`npm i --no-save playwright`, or a global install linked into
// web/node_modules). Run after `npm run build`:   node web/scripts/e2e-local.mjs [screenshot-dir]
// Checks: pairing with the match code, pull + decrypt + render, the manifest states (verified / incomplete / replay),
// markup stays text, no console error or CSP violation, the service worker serves the page offline, the web manifest.
import http from "node:http";
import { mkdirSync, readFileSync } from "node:fs";
import { chromium } from "playwright";
import { makeFetch } from "../../worker/src/entry.js";
import { makeMemoryBackend } from "../../worker/test/support/memory-backend.js";
import { decode, encode } from "../src/b64url.js";
import { deriveItemId, deriveKPair, generatePairKeys, importDataKey, matchCode, sealItem } from "../src/crypto.js";
import { idsHash } from "../src/manifest.js";

const dist = new URL("../dist/", import.meta.url).pathname;
const shots = process.argv[2] ?? "/tmp/mirror-e2e";
mkdirSync(shots, { recursive: true });
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".webmanifest": "application/manifest+json", ".png": "image/png" };
const headersFile = readFileSync(`${dist}_headers`, "utf8");
const csp = headersFile.match(/Content-Security-Policy: (.*)/)[1];

const backend = makeMemoryBackend();
const env = {
  ASSETS: {
    fetch: async (req) => {
      const path = new URL(req.url).pathname === "/" ? "/index.html" : new URL(req.url).pathname;
      try {
        const ext = path.slice(path.lastIndexOf("."));
        return new Response(readFileSync(dist + path), { headers: { "content-type": types[ext] ?? "text/plain", "content-security-policy": csp, ...(path === "/sw.js" ? { "cache-control": "no-cache" } : {}) } });
      } catch {
        return new Response("not found", { status: 404 });
      }
    },
  },
};
const fetchHandler = makeFetch(() => backend);
let serveOlderState = false; // simulates a server that answers with a lower head seq
const server = http.createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  if (serveOlderState && /\/items\?/.test(req.url)) {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ items: [], seq: 1, more: false }));
  }
  const init = { method: req.method, headers: req.headers };
  if (chunks.length && !["GET", "HEAD"].includes(req.method)) init.body = Buffer.concat(chunks);
  const r = await fetchHandler(new Request(`http://localhost${req.url}`, init), env);
  res.writeHead(r.status, Object.fromEntries(r.headers));
  res.end(Buffer.from(await r.arrayBuffer()));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = `http://127.0.0.1:${server.address().port}`;
const api = async (method, path, body, auth) => {
  const r = await fetch(origin + path, { method, headers: { "content-type": "application/json", ...(auth ? { authorization: auth } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, json: await r.json().catch(() => null) };
};
const sha = async (t) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(t)))].map((b) => b.toString(16).padStart(2, "0")).join("");

let failures = 0;
const check = (name, ok, extra = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${extra ? "  " + extra : ""}`);
  if (!ok) failures += 1;
};

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1100, height: 720 }, deviceScaleFactor: 2 });
const page = await context.newPage();
const problems = [];
page.on("console", (m) => { if (["error", "warning"].includes(m.type())) problems.push(`${m.type()}: ${m.text()}`); });
page.on("pageerror", (e) => problems.push("pageerror: " + e.message));
await page.addInitScript(() => {
  const sub = crypto.subtle;
  const exp = sub.exportKey.bind(sub);
  sub.exportKey = async (...a) => { const r = await exp(...a); if (a[0] === "raw" && r.byteLength === 65) window.__pub = Array.from(new Uint8Array(r)); return r; };
  const grv = crypto.getRandomValues.bind(crypto);
  crypto.getRandomValues = (arr) => { const r = grv(arr); if (arr instanceof Uint8Array && arr.length === 16) window.__nonce = Array.from(arr); return r; };
});

// MARK: Pair a JS phone

await page.goto(origin + "/");
await page.waitForSelector("svg.qr");
await page.screenshot({ path: `${shots}/1-qr.png` });
const browserPub = Uint8Array.from(await page.evaluate(() => window.__pub));
const nonce = Uint8Array.from(await page.evaluate(() => window.__nonce));
const slotId = backend.gate.sql.all("SELECT pairId FROM slots")[0].pairId;
const ownerToken = encode(crypto.getRandomValues(new Uint8Array(32)));
const ownerDev = encode(crypto.getRandomValues(new Uint8Array(16)));
const made = await api("POST", "/api/mirrors", { deviceId: ownerDev, ownerTokenHash: await sha(ownerToken) });
const mirrorId = made.json.mirrorId;
const owner = `Bearer ${ownerDev}.${ownerToken}`;
const phone = await generatePairKeys();
await api("POST", `/api/pair/${slotId}/join`, { phonePub: encode(phone.publicRaw) });
const phoneCode = await matchCode(browserPub, phone.publicRaw, nonce);
await page.waitForSelector("#codes-match", { timeout: 6000 });
check("the page and the phone show the same code", (await page.locator(".code").textContent()).trim() === phoneCode);
await page.screenshot({ path: `${shots}/2-confirm.png` });
await page.click("#codes-match");
const dataKey = crypto.getRandomValues(new Uint8Array(32));
const devId = encode(crypto.getRandomValues(new Uint8Array(16)));
const devTok = encode(crypto.getRandomValues(new Uint8Array(32)));
await api("POST", `/api/m/${mirrorId}/devices`, { deviceId: devId, tokenHash: await sha(devTok) }, owner);
const kPair = await deriveKPair(phone.privateKey, browserPub, nonce);
const iv = crypto.getRandomValues(new Uint8Array(12));
const wrap = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: new TextEncoder().encode(`palabra-mirror-wrap-v1|${slotId}`), tagLength: 128 }, kPair, new TextEncoder().encode(JSON.stringify({ v: 1, mirrorId, deviceId: devId, deviceToken: devTok, dataKey: encode(dataKey) }))));
await api("POST", `/api/pair/${slotId}/reply`, { sealed: encode(new Uint8Array([...iv, ...wrap])) });
await page.waitForSelector("#refresh", { timeout: 15000 });

// MARK: A phone that pushes data items and manifests

const keys = await importDataKey(dataKey);
let generation = 1;
const live = new Map(); // item id -> true
async function item(kind, recordId, d, g) {
  const id = await deriveItemId(keys, kind, recordId);
  const plain = new TextEncoder().encode(JSON.stringify({ v: 1, k: kind, r: recordId, h: "h", g, d }));
  return { id, sealed: encode(await sealItem(keys, id, plain)) };
}
async function pushWords(list) {
  generation += 1;
  const items = [];
  for (const [i, [spanish, translation, createdAt]] of list.entries()) {
    const built = await item("word", `w-${spanish}-${i}`, { spanish, translation, category: "Test", tags: ["t"], createdAt }, generation);
    live.set(built.id, true);
    items.push(built);
  }
  return (await api("PUT", `/api/m/${mirrorId}/items`, { items }, owner)).status;
}
async function pushManifest({ extraCount = 0, pushedAt = new Date().toISOString().replace(/\.\d+Z$/, "Z") } = {}) {
  generation += 1;
  const ids = [...live.keys()];
  const m = await item("manifest", "manifest", { counts: { word: ids.length + extraCount }, idsHash: await idsHash(ids), pushedAt }, generation);
  return (await api("PUT", `/api/m/${mirrorId}/items`, { items: [m] }, owner)).status;
}
// Click Refresh, give the pull a moment to start, then wait until the "Updating…" line is gone and the screen has settled.
const refresh = async () => {
  await page.click("#refresh");
  await page.waitForTimeout(300);
  await page.waitForFunction(() => !document.body.innerText.includes("Updating…"), null, { timeout: 15000 });
  await page.waitForTimeout(150);
};
const bodyText = () => page.evaluate(() => document.body.innerText);

// 1. a complete copy is verified and shows when the phone synced
await pushWords([["<img src=x onerror=window.__pwned=1>", "tomorrow", "2026-01-02T00:00:00Z"], ["مرحبا", "hello", "2026-01-03T00:00:00Z"], ["casa", "house", "2026-01-04T00:00:00Z"]]);
await pushManifest();
await refresh();
let text = await bodyText();
check("words are listed", (await page.locator("li.row").count()) === 3);
check("markup stays text", text.includes("<img src=x onerror=window.__pwned=1>") && (await page.evaluate(() => window.__pwned ?? null)) === null);
check("the badge says when the phone synced", text.includes("Phone synced:"));
check("a verified copy shows no warning", !text.includes("Still receiving") && !text.includes("Not verified yet"));
await page.screenshot({ path: `${shots}/3-verified.png` });

// 2. the manifest promises one more item than exists: incomplete, then complete
await pushManifest({ extraCount: 1 });
await refresh();
text = await bodyText();
check("an incomplete copy says so", text.includes("Still receiving from your phone…"));
await page.screenshot({ path: `${shots}/4-incomplete.png` });
await pushWords([["libro", "book", "2026-01-05T00:00:00Z"]]);
await pushManifest();
await refresh();
text = await bodyText();
check("the copy completes when the missing item arrives", !text.includes("Still receiving") && (await page.locator("li.row").count()) === 4);

// 3. a server answering with older state is refused and the saved copy stays
serveOlderState = true;
await refresh();
text = await bodyText();
check("a replay shows the banner and keeps the list", text.includes("The server sent older data than this computer already has") && (await page.locator("li.row").count()) === 4);
await page.screenshot({ path: `${shots}/5-replay.png` });
serveOlderState = false;
await refresh();
check("the banner goes away once the server is sane", !(await bodyText()).includes("The server sent older data"));

// 4. dark mode and a narrow window
await page.emulateMedia({ colorScheme: "dark" });
await page.screenshot({ path: `${shots}/6-dark.png` });
await page.setViewportSize({ width: 390, height: 780 });
await page.screenshot({ path: `${shots}/7-narrow-dark.png` });
await page.setViewportSize({ width: 1100, height: 720 });
await page.emulateMedia({ colorScheme: "light" });

// 5. installable and offline (the console is checked before going offline: a blocked network is an expected error)
check("no console errors or CSP violations", problems.length === 0, problems.join(" | "));
const manifest = await page.evaluate(async () => { const r = await fetch("/manifest.webmanifest"); return { ok: r.ok, json: await r.json() }; });
check("the web manifest is served as JSON with icons", manifest.ok && manifest.json.icons.length === 3);
await page.reload();
await page.evaluate(() => navigator.serviceWorker.ready);
await page.waitForFunction(() => navigator.serviceWorker.controller !== null, null, { timeout: 10000 }).catch(async () => { await page.reload(); });
await context.setOffline(true);
await page.reload();
await page.waitForSelector("li.row", { timeout: 10000 });
check("offline reload still shows the saved words", (await page.locator("li.row").count()) === 4);
await page.screenshot({ path: `${shots}/8-offline.png` });
await context.setOffline(false);

await browser.close();
server.close();
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
