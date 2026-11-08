// Post-deploy check against a live Worker: node worker/scripts/smoke.mjs <baseUrl>
// Uses only fetch and Web Crypto. Creates one throwaway mirror and one throwaway pairing slot.

const base = (process.argv[2] ?? "").replace(/\/+$/, "");
if (!/^https?:\/\//.test(base)) {
  console.error("usage: node smoke.mjs <baseUrl>   (for example https://palabra-mirror.you.workers.dev)");
  process.exit(2);
}

const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
const random = (n) => b64url(crypto.getRandomValues(new Uint8Array(n)));
const sha256Hex = async (text) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))].map((b) => b.toString(16).padStart(2, "0")).join("");

let step = 0;
const cors = [];
function check(name, condition, detail = "") {
  step += 1;
  if (!condition) {
    console.error(`FAIL ${step} - ${name}${detail ? `: ${detail}` : ""}`);
    process.exit(1);
  }
  console.log(`ok ${step} - ${name}`);
}

async function call(method, path, { body, auth } = {}) {
  const headers = {};
  if (auth) headers.authorization = auth;
  if (body !== undefined) headers["content-type"] = "application/json";
  const res = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  for (const [name] of res.headers) if (name.toLowerCase().startsWith("access-control-")) cors.push(`${method} ${path}: ${name}`);
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: res.status, json, headers: res.headers, text };
}

const home = await fetch(base + "/");
const csp = home.headers.get("content-security-policy") ?? "";
check("GET / is 200", home.status === 200, String(home.status));
check("the page carries frame-ancestors 'none' in its CSP", csp.includes("frame-ancestors 'none'"), csp || "(no CSP header)");

const deviceId = random(16);
const token = random(32);
const owner = `Bearer ${deviceId}.${token}`;
const made = await call("POST", "/api/mirrors", { body: { deviceId, ownerTokenHash: await sha256Hex(token) } });
check("POST /api/mirrors is 201", made.status === 201 && typeof made.json?.mirrorId === "string", `${made.status} ${made.text.slice(0, 120)}`);
const m = `/api/m/${made.json.mirrorId}`;

const itemId = random(16);
const put = await call("PUT", `${m}/items`, { auth: owner, body: { items: [{ id: itemId, sealed: "AAAA" }] } });
check("PUT items is 200 with seq 1", put.status === 200 && put.json?.seq === 1, `${put.status} ${put.text.slice(0, 120)}`);

const list = await call("GET", `${m}/items?since=0`, { auth: owner });
check("GET items returns the item", list.status === 200 && list.json?.items?.length === 1 && list.json.items[0].id === itemId && list.json.items[0].sealed === "AAAA", list.text.slice(0, 160));

const wrong = await call("GET", `${m}/items?since=0`, { auth: `Bearer ${deviceId}.${random(32)}` });
check("a wrong token is 401", wrong.status === 401, String(wrong.status));

const start = await call("POST", "/api/pair/start");
check("POST /api/pair/start is 201", start.status === 201 && typeof start.json?.pairId === "string", `${start.status} ${start.text.slice(0, 120)}`);
const pair = `/api/pair/${start.json.pairId}`;
const join = await call("POST", `${pair}/join`, { body: { phonePub: random(65) } });
check("pair join is 200", join.status === 200, `${join.status} ${join.text.slice(0, 120)}`);
const joined = await call("GET", pair);
check("pair poll shows joined", joined.json?.state === "joined", joined.text.slice(0, 120));
const cancel = await call("POST", `${pair}/cancel`);
check("pair cancel is 200", cancel.status === 200, String(cancel.status));
const cancelled = await call("GET", pair);
check("pair poll shows cancelled", cancelled.json?.state === "cancelled", cancelled.text.slice(0, 120));

check("no response carries an access-control header", cors.length === 0, cors.join("; "));
console.log(`smoke passed against ${base}`);
