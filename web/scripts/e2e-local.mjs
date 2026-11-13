// A real-browser check of the whole page against the Worker's real router (in memory), with a JavaScript "phone".
// NOT run by CI: it needs Playwright and a Chromium (`npm i --no-save playwright`, or a global install linked into
// web/node_modules). Run after `npm run build`:   node web/scripts/e2e-local.mjs [screenshot-dir]
// Checks: pairing with the match code, pull + decrypt + render, the manifest states (verified / incomplete / replay),
// every collection (study, review, artifacts, chat, books) on its screen with every nav link and detail route,
// a key rotation with two paired computers (one removed, one rekeys and shows the re-pushed words, nothing old is kept),
// markup stays text, no console error or CSP violation, the service worker serves the page offline, the web manifest.
import http from "node:http";
import { mkdirSync, readFileSync } from "node:fs";
import { chromium } from "playwright";
import { makeFetch } from "../../worker/src/entry.js";
import { makeMemoryBackend } from "../../worker/test/support/memory-backend.js";
import { decode, encode } from "../src/b64url.js";
import { deriveItemId, deriveKPair, generatePairKeys, importDataKey, matchCode, openItem, sealItem } from "../src/crypto.js";
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
// Lets the script (playing the phone) read the page's public key and nonce, which the real phone gets from the QR code.
const capture = () => {
  const sub = crypto.subtle;
  const exp = sub.exportKey.bind(sub);
  sub.exportKey = async (...a) => { const r = await exp(...a); if (a[0] === "raw" && r.byteLength === 65) window.__pub = Array.from(new Uint8Array(r)); return r; };
  const grv = crypto.getRandomValues.bind(crypto);
  crypto.getRandomValues = (arr) => { const r = grv(arr); if (arr instanceof Uint8Array && arr.length === 16) window.__nonce = Array.from(arr); return r; };
};
await page.addInitScript(capture);

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
const live = new Map(); // item id -> kind
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
    live.set(built.id, "word");
    items.push(built);
  }
  return (await api("PUT", `/api/m/${mirrorId}/items`, { items }, owner)).status;
}
async function pushManifest({ extraCount = 0, pushedAt = new Date().toISOString().replace(/\.\d+Z$/, "Z") } = {}) {
  generation += 1;
  const ids = [...live.keys()];
  const counts = {};
  for (const kind of live.values()) counts[kind] = (counts[kind] ?? 0) + 1;
  counts.word = (counts.word ?? 0) + extraCount;
  const m = await item("manifest", "manifest", { counts, idsHash: await idsHash(ids), pushedAt }, generation);
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

// 3b. every collection: one record of each kind, then every nav link and detail route in a real browser
const MARKUP = "<img src=x onerror=window.__pwned=1>";
async function pushRecords(list) {
  generation += 1;
  const items = [];
  for (const [kind, recordId, d] of list) {
    const built = await item(kind, recordId, d, generation);
    live.set(built.id, kind);
    items.push(built);
  }
  return (await api("PUT", `/api/m/${mirrorId}/items`, { items }, owner)).status;
}
const iso = "2026-11-09T21:30:00Z";
await pushRecords([
  ["deck", "d1", { id: "d1", name: MARKUP, kind: "user", createdAt: iso, counts: { total: 2, due: 1, new: 1 }, countsAt: iso }],
  ["deck", "dv", { id: "dv", name: "Vocabulary", kind: "vocabulary", createdAt: iso, counts: { total: 4, due: 0, new: 4 }, countsAt: iso }],
  ["card", "c1", { id: "c1", deckId: "d1", front: MARKUP, back: "back one", due: iso, reps: 0, lapses: 0, phase: "new", createdAt: iso }],
  ["stats", "stats", { reviewedToday: 4, streak: 7, lastSevenDays: [1, 2, 3, 4, 5, 6, 7], asOf: iso }],
  ["review", "n1", { id: "n1", wordId: "w-casa-2", headword: "casa", translation: MARKUP, score: 0.4, note: MARKUP, flagCount: 2, updatedAt: iso }],
  ["artifact", "a1", { id: "a1", title: MARKUP, kind: "spec", version: 1, updatedAt: iso, blocks: [
    { type: "heading", level: 1, text: MARKUP },
    { type: "table", columns: [{ title: "Word" }], rows: [[MARKUP], ["casa"]] },
    { type: "chart", style: "bar", title: "Words per day", labels: ["Mon", "Tue", "Wed"], series: [{ name: "Words", values: [3, 5, 2] }] },
    { type: "checklist", id: "c", items: [MARKUP] },
  ] }],
  ["artifact", "a2", { id: "a2", title: "A game", kind: "app", version: 1, updatedAt: iso, blocks: null }],
  ["chat", "latest", { id: "ch1", title: "About casa", wordId: null, updatedAt: iso, turns: [
    { role: "user", text: `${MARKUP}\nsecond line`, createdAt: iso, status: "sent" },
    { role: "assistant", text: "مرحبا بك", createdAt: iso, status: "sent" },
  ] }],
  ["lesson", "les1", { id: "les1", version: 1, title: "الدرس الأول", summary: MARKUP, bookId: "history", bookTitle: "التاريخ", chapterId: "u1", chapterTitle: "الوحدة الأولى", language: "ar", pageIds: ["p1", "p2"], terms: { t1: { term: MARKUP, definition: "تعريف" } }, notes: [] }],
  ["lessonPage", "les1/p1", { lessonId: "les1", id: "p1", number: 1, title: "الصفحة الأولى", dateLabel: null, blocks: [{ type: "paragraph", text: `نص عربي ${MARKUP} {{مصطلح|t1}}` }, { type: "keyPoint", label: "مهم", text: "نقطة" }] }],
  ["lessonPage", "les1/p2", { lessonId: "les1", id: "p2", number: 2, title: "الصفحة الثانية", dateLabel: "١٩٥٤", blocks: [{ type: "timeline", events: [{ date: "1954", title: "بداية" }] }, { type: "hologram" }] }],
]);
await pushManifest();
await refresh();
const gotoSection = async (href) => {
  await page.click(`a.nav-link[href="${href}"]`);
  await page.waitForFunction((h) => location.hash === h, href);
  await page.waitForTimeout(200);
};
const markupIsText = async (name) => {
  const body = await bodyText();
  check(`${name}: markup is shown as text`, body.includes("<img src=x onerror=window.__pwned=1>"));
  check(`${name}: nothing was built from it`, (await page.locator("img").count()) === 0 && (await page.evaluate(() => window.__pwned ?? null)) === null);
};
check("every kind arrived: the copy is verified", !(await bodyText()).includes("Still receiving"));

await gotoSection("#/study");
text = await bodyText();
check("Study shows the deck counts, the cards and the streak", text.includes("Total 2 · Due 1 · New 1") && text.includes("Vocabulary") && text.includes("Day streak"));
await page.click("summary");
await markupIsText("Study");
await page.screenshot({ path: `${shots}/9-study.png` });

await gotoSection("#/review");
await markupIsText("Need Review");
check("a need links to its word", (await page.locator('a.headword[href^="#/words/"]').count()) === 1);
await page.screenshot({ path: `${shots}/10-review.png` });

await gotoSection("#/artifacts");
check("the app artifact is listed as open-on-phone", (await bodyText()).includes("Open this on your phone"));
await page.click('a.headword[href^="#/artifacts/"]');
await page.waitForSelector(".artifact-page");
await markupIsText("Artifact");
check("the chart has three bars and a values table", (await page.locator("svg.chart-svg rect").count()) === 3 && (await page.locator("table.chart-values").count()) === 1);
await page.screenshot({ path: `${shots}/11-artifact.png` });

await gotoSection("#/chat");
await markupIsText("Chat");
check("chat keeps order and the line break", (await page.locator("li.turn").count()) === 2 && (await page.locator("li.turn br").count()) === 1);
await page.screenshot({ path: `${shots}/12-chat.png` });

await gotoSection("#/books");
await page.click('a.headword[href^="#/books/"]');
await page.waitForSelector(".reader");
await markupIsText("Books reader");
check("the Arabic lesson reads right to left even in an English browser", (await page.locator('.reader[dir="rtl"]').count()) === 1 && (await page.locator("article.lesson-page").count()) === 2);
check("lesson markup is plain text (the term keeps its words)", (await bodyText()).includes("مصطلح") && !(await bodyText()).includes("{{"));
await page.screenshot({ path: `${shots}/13-books-reader.png` });
await page.emulateMedia({ colorScheme: "dark" });
await page.screenshot({ path: `${shots}/14-books-reader-dark.png` });
await page.setViewportSize({ width: 390, height: 780 });
await page.screenshot({ path: `${shots}/15-books-reader-narrow.png` });
await page.setViewportSize({ width: 1100, height: 720 });
await page.emulateMedia({ colorScheme: "light" });

await gotoSection("#/words");
await page.click("a.headword");
await page.waitForSelector(".detail-section, .meta");
check("a word opens its detail page", (await page.locator("a.back").count()) === 1);
await page.screenshot({ path: `${shots}/16-word-detail.png` });
await page.evaluate(() => { location.hash = "#/words/does-not-exist"; });
await page.waitForTimeout(200);
check("a route to a vanished item says so", (await bodyText()).includes("That item is gone"));
await gotoSection("#/words");

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

// MARK: 6. Key rotation: two paired computers (with device keys), the phone removes one

const rand = (n) => crypto.getRandomValues(new Uint8Array(n));
const seenSlots = new Set([slotId]);
const rotationProblems = [];
async function pairComputer() {
  const ctx = await browser.newContext({ viewport: { width: 1100, height: 720 } });
  const p = await ctx.newPage();
  p.on("console", (m) => { if (["error", "warning"].includes(m.type()) && !m.text().startsWith("Failed to load resource")) rotationProblems.push(`${m.type()}: ${m.text()}`); });
  p.on("pageerror", (e) => rotationProblems.push("pageerror: " + e.message));
  await p.addInitScript(capture);
  await p.goto(origin + "/");
  await p.waitForSelector("svg.qr");
  const pub = Uint8Array.from(await p.evaluate(() => window.__pub));
  const n = Uint8Array.from(await p.evaluate(() => window.__nonce));
  const slot = backend.gate.sql.all("SELECT pairId FROM slots").map((r) => r.pairId).find((id) => !seenSlots.has(id));
  seenSlots.add(slot);
  const pk = await generatePairKeys();
  await api("POST", `/api/pair/${slot}/join`, { phonePub: encode(pk.publicRaw) });
  await p.waitForSelector("#codes-match", { timeout: 6000 });
  await p.click("#codes-match");
  const deviceId = encode(rand(16));
  const deviceToken = encode(rand(32));
  const deviceKey = rand(32);
  await api("POST", `/api/m/${mirrorId}/devices`, { deviceId, tokenHash: await sha(deviceToken) }, owner);
  const k = await deriveKPair(pk.privateKey, pub, n);
  const wrapIv = rand(12);
  const sealedWrap = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: wrapIv, additionalData: new TextEncoder().encode(`palabra-mirror-wrap-v1|${slot}`), tagLength: 128 }, k, new TextEncoder().encode(JSON.stringify({ v: 1, mirrorId, deviceId, deviceToken, dataKey: encode(dataKey), deviceKey: encode(deviceKey) }))));
  await api("POST", `/api/pair/${slot}/reply`, { sealed: encode(new Uint8Array([...wrapIv, ...sealedWrap])) });
  await p.waitForSelector("#refresh", { timeout: 15000 });
  return { ctx, page: p, deviceId, deviceKey };
}
const pull = async (p) => {
  await p.click("#refresh");
  await p.waitForTimeout(300);
  await p.waitForFunction(() => !document.body.innerText.includes("Updating…"), null, { timeout: 15000 });
  await p.waitForTimeout(250);
};
// What a page's IndexedDB holds: the rows (no secrets) and the epoch it believes it is at.
const stored = (p) =>
  p.evaluate(
    () =>
      new Promise((resolve, reject) => {
        const open = indexedDB.open("palabra-mirror");
        open.onerror = () => reject(open.error);
        open.onsuccess = () => {
          const db = open.result;
          const tx = db.transaction(["items", "meta"]);
          const rows = tx.objectStore("items").getAll();
          const creds = tx.objectStore("meta").get("creds");
          tx.oncomplete = () => { db.close(); resolve({ rows: rows.result.map((r) => ({ id: r.id, kind: r.kind, recordId: r.recordId })), epoch: creds.result?.epoch ?? null, paired: Boolean(creds.result) }); };
        };
      }),
  );

const A = await pairComputer();
const B = await pairComputer();
await pull(B.page);
check("before the rotation both new computers show the library", (await B.page.locator("li.row").count()) === 4);
await pull(A.page);
check("computer A shows the library too", (await A.page.locator("li.row").count()) === 4);
const oldIds = new Set(live.keys());

// The phone removes A: a new key sealed to B's device key only. The first computer (no blob) is dropped with A.
const newKey = rand(32);
const epoch = 1;
const blobKey = await crypto.subtle.importKey("raw", B.deviceKey, { name: "AES-GCM" }, false, ["encrypt"]);
const blobIv = rand(12);
const blob = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: blobIv, additionalData: new TextEncoder().encode(`palabra-mirror-rotate-v1|${mirrorId}|${B.deviceId}|${epoch}`), tagLength: 128 }, blobKey, new TextEncoder().encode(JSON.stringify({ v: 1, epoch, dataKey: encode(newKey) }))));
const rotated = await api("POST", `/api/m/${mirrorId}/rotate`, { epoch, remove: A.deviceId, blobs: { [B.deviceId]: encode(new Uint8Array([...blobIv, ...blob])) } }, owner);
check("the Worker takes the rotation and drops A and the computer that got no blob", rotated.status === 200 && rotated.json.removed.includes(A.deviceId) && rotated.json.removed.includes(devId) && !rotated.json.removed.includes(B.deviceId), JSON.stringify(rotated));

// The phone sends everything again under the new key.
const keys2 = await importDataKey(newKey);
generation += 1;
const fresh = [];
for (const [spanish, translation] of [["nuevo", "new"], ["otro", "other"]]) {
  const id = await deriveItemId(keys2, "word", `w-${spanish}`);
  const plain = new TextEncoder().encode(JSON.stringify({ v: 1, k: "word", r: `w-${spanish}`, h: "h", g: generation, d: { spanish, translation, category: "Test", tags: [], createdAt: "2026-11-10T00:00:00Z" } }));
  fresh.push({ id, sealed: encode(await sealItem(keys2, id, plain)) });
}
const mid = await deriveItemId(keys2, "manifest", "manifest");
const mplain = new TextEncoder().encode(JSON.stringify({ v: 1, k: "manifest", r: "manifest", h: "h", g: generation + 1, d: { counts: { word: 2 }, idsHash: await idsHash(fresh.map((f) => f.id)), pushedAt: new Date().toISOString().replace(/\.\d+Z$/, "Z") } }));
fresh.push({ id: mid, sealed: encode(await sealItem(keys2, mid, mplain)) });
check("the re-push under the new key is accepted", (await api("PUT", `/api/m/${mirrorId}/items`, { items: fresh }, owner)).status === 200);

// A: removed. Its copy is gone.
await pull(A.page);
check("the removed computer is told so", (await A.page.evaluate(() => document.body.innerText)).includes("This computer was removed"));
const aStored = await stored(A.page);
check("the removed computer keeps nothing", aStored.rows.length === 0 && !aStored.paired);
await A.page.screenshot({ path: `${shots}/17-removed.png` });
// The first computer (paired before any device key) is removed as well.
await pull(page);
check("a computer with no blob is removed too", (await bodyText()).includes("This computer was removed"));

// B: follows the rotation.
await pull(B.page);
const bText = await B.page.evaluate(() => document.body.innerText);
check("the computer that got the key rekeys and shows the re-pushed words", (await B.page.locator("li.row").count()) === 2 && bText.includes("nuevo") && bText.includes("otro"), bText.slice(0, 120));
check("it does not say removed, and the copy is verified", !bText.includes("This computer was removed") && !bText.includes("Still receiving") && !bText.includes("Not verified yet"));
const bStored = await stored(B.page);
let allNewKey = bStored.rows.length === 3;
for (const row of bStored.rows) allNewKey &&= row.id === (await deriveItemId(keys2, row.kind, row.recordId)) && !oldIds.has(row.id);
check("every row it holds is named by the new key, none by the old", allNewKey);
check("it is now at epoch 1", bStored.epoch === 1);
await B.page.screenshot({ path: `${shots}/18-rekeyed.png` });

// The Worker holds nothing sealed under the old key.
const onWorker = (await api("GET", `/api/m/${mirrorId}/items?since=0&limit=200`, undefined, owner)).json.items;
let noneOpenWithOld = true;
for (const it of onWorker) noneOpenWithOld &&= await openItem(keys, it.id, decode(it.sealed)).then(() => false, () => true);
check("the Worker holds only the new items, and the old key opens none of them", onWorker.length === 3 && onWorker.every((it) => !oldIds.has(it.id)) && noneOpenWithOld);
check("no console error or CSP violation on the rotation pages", rotationProblems.length === 0, rotationProblems.join(" | "));
await A.ctx.close();
await B.ctx.close();

await browser.close();
server.close();
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
