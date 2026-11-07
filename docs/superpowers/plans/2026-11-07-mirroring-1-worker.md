# Mirroring, plan 1: the Worker

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deployable Cloudflare Worker that serves the web app's files and holds the encrypted mirror: pairing slots, mirrors, devices and sealed items, behind a REST API with limits, tests and a deploy workflow that smoke-tests the live Worker.

**Architecture:** All logic lives in plain JavaScript classes over a small SQL adapter (`GateStore`, `MirrorStore`) and one pure router (`handleApi`), tested in Node against `node:sqlite`. Two thin Durable Object classes (`Gate` singleton, `Mirror` per mirror id) wrap the stores and expose them as RPC methods; `worker.js` routes `/api/*` to the router and everything else to the static-assets binding. The server only ever stores ciphertext and token hashes.

**Tech Stack:** Cloudflare Workers + SQLite-backed Durable Objects, Workers Static Assets, plain ESM JavaScript (no build step for the Worker), Node 22 (`node --test`, `node:sqlite`), `wrangler` 4 (dry-run and deploy), GitHub Actions on ubuntu.

**Spec:** `docs/superpowers/specs/2026-11-07-mirroring-design.md` (sections: Cloudflare side, Keys and sealing, Pairing, Phases 1).

## Global Constraints

- The server never sees a token, key or plaintext. Clients generate every token and send only its SHA-256 (64 lowercase hex characters). No request or response body is logged.
- Bearer format: `Authorization: Bearer <deviceId>.<token>`; `deviceId` and `token` are base64url without padding.
- Ids (`mirrorId`, `pairId`) are 16 random bytes as 22-character base64url. Item ids are 16..64 characters of base64url.
- Pairing slot lifetime 120 seconds, single join, reply read once.
- Caps (in `src/limits.js`, one place): body 1,048,576 bytes; one sealed item 262,144 characters; 200 items per PUT; list page at most 200 items and about 900,000 sealed characters; 20,000 items per mirror; 8 browser devices per mirror. Rates: mirrors create 5 per hour per IP; pair start 10 and pair join 20 per 10 minutes per IP; pair poll 300 per 10 minutes per IP; items PUT 120 per minute per device; items GET 240 per minute per device.
- Error body is always `{"error": "<code>"}` with the status codes 400 `bad_request`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 405 `method_not_allowed`, 409 (specific code), 410 `gone`, 413 `too_large`, 429 `rate_limited` (plus a `Retry-After` header).
- No CORS headers anywhere (same origin only). API responses carry `Cache-Control: no-store`.
- Static assets get this CSP from `web/public/_headers`: `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`.
- Store methods return result objects (`{ok: true, ...}` or `{ok: false, status, error}`), never throw for expected failures, because errors thrown across a Durable Object call lose their class.
- Repo rules that apply: work on `main`; the workflow must not touch the iOS workflow `build-ipa.yml`; CI cannot run workerd, so the real runtime is verified by the post-deploy smoke test.

## Review Focus

- A request body exactly at the cap passes, one byte over gets 413 (and nothing is written).
- A PUT batch containing one malformed item, or the same id twice, writes nothing at all.
- A slot read at exactly 120 seconds is still live, at 121 is `gone`; a join after a reply, and a poll after the reply was read, are refused.
- A revoked device's token stops working on its very next request.
- Odd paths and headers (`/api/m/../x`, a mirror id with the wrong length, an `Authorization` header with unicode or 10 KB of text) are 404/401, never a crash.

---

## File structure

```
worker/package.json  wrangler.toml  .gitignore
worker/src/limits.js     constants (the Global Constraints numbers)
worker/src/sql.js        adapters: nodeSqlite(db) for tests, durableSql(ctx.storage) for Cloudflare
worker/src/auth.js       sha256Hex, randomId, parseBearer, timingSafeEqualHex, isHex64, isB64url
worker/src/rate.js       fixed-window counter over a `rates` table
worker/src/store.js      MirrorStore (devices, items)
worker/src/gate.js       GateStore (pairing slots, IP rate counters)
worker/src/router.js     handleApi(request, backend, opts) -> Response
worker/src/entry.js      makeFetch(getBackend): /api/* -> router, else ASSETS
worker/src/do.js         Gate and Mirror Durable Object classes, DoBackend
worker/src/worker.js     default export + class exports (the wrangler entry)
worker/scripts/smoke.mjs post-deploy check against a live URL
worker/test/             *.test.js and support/memory-backend.js
web/package.json  web/scripts/build.mjs  web/public/index.html  web/public/_headers
.github/workflows/mirror.yml
docs/features/mirroring.md
```

---

### Task 1: Scaffold, placeholder page, CI test job

**Files:**
- Create: `worker/package.json`, `worker/wrangler.toml`, `worker/.gitignore`, `worker/src/worker.js` (placeholder), `web/package.json`, `web/scripts/build.mjs`, `web/public/index.html`, `web/public/_headers`, `web/test/build.test.js`, `.github/workflows/mirror.yml`

**Interfaces:**
- Produces: `npm --prefix web run build` copies `web/public/*` to `web/dist/` (later plans extend the script); `npm --prefix worker test` runs `node --test test/`; `npm --prefix worker run check` runs `wrangler deploy --dry-run --outdir dist-check`.

- [ ] **Step 1: Write the failing test** `web/test/build.test.js` (node:test): runs `node web/scripts/build.mjs`, then asserts `web/dist/index.html` exists and contains `Palabra`, and `web/dist/_headers` exists and contains `frame-ancestors 'none'` and `script-src 'self'`.
- [ ] **Step 2: Run it to see it fail:** `node --test web/test/` -> FAIL (build script missing).
- [ ] **Step 3: Implement** `web/scripts/build.mjs` (empties `web/dist`, `fs.cpSync('web/public', 'web/dist', {recursive: true})`, paths resolved from the script's own location), `web/public/index.html` (a minimal page titled "Palabra Mirroring" with the text "The Worker is running. Pairing arrives next." and no script or style), `web/public/_headers` with the CSP above plus `X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer` under `/*`, `web/package.json` (`"type": "module"`, scripts `build`, `test`). `worker/package.json` (`"type": "module"`, `engines.node >= 22.13`, devDependency `wrangler ^4`, scripts `test`, `check`), `worker/wrangler.toml` (name `palabra-mirror`, `main = "src/worker.js"`, `compatibility_date = "2025-09-01"`, `[assets] directory = "../web/dist"`, `binding = "ASSETS"`, `run_worker_first = ["/api/*"]`), `worker/src/worker.js` exporting a default `fetch` that returns `new Response("ok")`, and `worker/.gitignore` (`node_modules`, `dist-check`, `.wrangler`). Run `npm install` in `worker/` and commit the lockfile.
- [ ] **Step 4: Run** `node --test web/test/` -> PASS; `npm --prefix worker run check` -> exits 0 (a dry-run bundle).
- [ ] **Step 5: Write `.github/workflows/mirror.yml`** with the `test` job only: triggers `push` to `main` filtered to `worker/**`, `web/**` and the workflow file, plus `workflow_dispatch`; `concurrency` group `mirror-${{ github.ref }}` with cancel-in-progress; ubuntu-latest, `actions/setup-node@v4` with node 22, `npm ci` in `worker`, then `npm --prefix web run build`, `node --test web/test/`, `npm --prefix worker test`, `npm --prefix worker run check`.
- [ ] **Step 6: Commit** `feat(mirror): worker and web scaffold, CI test job`.

---

### Task 2: Authentication helpers

**Files:**
- Create: `worker/src/auth.js`, `worker/test/auth.test.js`

**Interfaces:**
- Produces:
  - `sha256Hex(text: string): Promise<string>` (lowercase hex of UTF-8 bytes)
  - `randomId(bytes = 16): string` (base64url, no padding; 16 bytes -> 22 characters)
  - `parseBearer(header: string | null): {deviceId: string, token: string} | null`
  - `timingSafeEqualHex(a: string, b: string): boolean`
  - `isHex64(s: unknown): boolean`, `isB64url(s: unknown, min: number, max: number): boolean`

- [ ] **Step 1: Write failing tests** in `auth.test.js`: `sha256Hex("abc")` equals `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`; `parseBearer("Bearer dev1.tok2")` -> `{deviceId:"dev1", token:"tok2"}`; null for `null`, `""`, `"Bearer"`, `"Bearer nodot"`, `"Bearer a.b.c"`, `"bearer a.b"` (scheme is case-sensitive), a header over 300 characters, a token with `+`, `/`, `=` or non-ASCII characters; `randomId()` has length 22, matches `/^[A-Za-z0-9_-]{22}$/`, and 1000 calls are all distinct; `timingSafeEqualHex("ab","ab")` true, `("ab","ac")` false, different lengths false; `isHex64` accepts 64 lowercase hex, rejects uppercase, 63 or 65 characters; `isB64url("abc_-",1,10)` true, `("ab=",1,10)` false, length bounds respected.
- [ ] **Step 2: Run** `npm --prefix worker test` -> FAIL.
- [ ] **Step 3: Implement** the functions in `src/auth.js` using Web Crypto (`crypto.subtle.digest`, `crypto.getRandomValues`) so the same file runs in Node and workerd; the equality compares every character without early exit.
- [ ] **Step 4: Run** `npm --prefix worker test` -> PASS.
- [ ] **Step 5: Commit** `feat(mirror): auth helpers`.

---

### Task 3: SQL adapter, rate counter, MirrorStore

**Files:**
- Create: `worker/src/limits.js`, `worker/src/sql.js`, `worker/src/rate.js`, `worker/src/store.js`, `worker/test/store.test.js`, `worker/test/support/clock.js`

**Interfaces:**
- Consumes: `auth.js` (`sha256Hex`, `parseBearer`, `timingSafeEqualHex`, `isHex64`, `isB64url`).
- Produces:
  - `limits.js`: `export const LIMITS = {...}` with the Global Constraints numbers (keys: `bodyBytes`, `sealedChars`, `itemsPerPut`, `listMax`, `listSealedSoft`, `itemsTotal`, `browserDevices`, `pairTtlSec`, and `rates: {mirrorsCreate: [5, 3600], pairStart: [10, 600], pairJoin: [20, 600], pairPoll: [300, 600], itemsPut: [120, 60], itemsGet: [240, 60]}` as `[limit, windowSec]`). A store or gate built with `opts.limits` merges it shallowly over `LIMITS`, so a test overrides `rates` as a whole object.
  - `sql.js`: interface `Sql = {all(query: string, ...params): object[], run(query: string, ...params): void, transaction<T>(fn: () => T): T}`; `nodeSqlite(db: DatabaseSync): Sql`; `durableSql(storage: DurableObjectStorage): Sql` (uses `storage.sql.exec(...).toArray()` and `storage.transactionSync`).
  - `rate.js`: `checkRate(sql: Sql, key: string, limit: number, windowSec: number, now: number): {ok: true} | {ok: false, status: 429, error: "rate_limited", retryAfter: number}` over table `rates(key TEXT PRIMARY KEY, windowStart INTEGER, count INTEGER)` (created by `ensureRatesTable(sql)`).
  - `store.js`: `class MirrorStore { constructor(sql: Sql, opts?: {now?: () => number, limits?: Partial<typeof LIMITS>}); init(): void; create({deviceId, ownerTokenHash}): Result; authenticate(bearer: string | null, role?: "owner" | "browser"): Promise<Result & {device?: {deviceId, role}}>; addDevice(bearer, {deviceId, tokenHash}): Promise<Result>; listDevices(bearer): Promise<Result & {devices?: {deviceId, role, createdAt, lastSeen}[]}>; removeDevice(bearer, deviceId: string): Promise<Result>; putItems(bearer, items: {id: string, sealed: string, deleted?: boolean}[]): Promise<Result & {seq?: number}>; listItems(bearer, since: number, limit: number): Promise<Result & {items?: {id, seq, sealed, deleted}[], seq?: number, more?: boolean}>; state(bearer): Promise<Result & {seq?: number}> }` where `Result = {ok: true} | {ok: false, status: number, error: string}`. `now()` returns whole seconds.
  - Tables: `devices(deviceId TEXT PRIMARY KEY, role TEXT, tokenHash TEXT, createdAt INTEGER, lastSeen INTEGER)`, `items(id TEXT PRIMARY KEY, seq INTEGER NOT NULL, sealed TEXT NOT NULL, deleted INTEGER NOT NULL)` with an index on `seq`, `meta(key TEXT PRIMARY KEY, value INTEGER)` holding `seq`, plus `rates`.

- [ ] **Step 1: Write failing tests** in `store.test.js` (a `makeStore(opts)` helper builds an in-memory `DatabaseSync`, `nodeSqlite`, a `MirrorStore` and a controllable clock). Cases, each with the exact assertions:
  - `create` makes one owner device; a second `create` returns `{ok:false, status:409, error:"already_created"}`.
  - `authenticate` with the right bearer returns the device and role; wrong token, unknown device and a bad header are all `401 unauthorized`; asking for role `owner` with a browser token is `403 forbidden`.
  - `addDevice` by the owner works and the browser can then authenticate; a browser token calling `addDevice` is 403; a 9th browser is `409 too_many_devices`; a duplicate `deviceId` is `409 device_exists`; a malformed `tokenHash` (not 64 lowercase hex) is `400 bad_request`.
  - `removeDevice`: after removal the browser's very next `authenticate` is 401; removing the owner is `400 owner_device`; unknown id is 404.
  - `putItems`: returns increasing `seq` (3 items -> seq 3); upserting an existing id replaces the row and gives it a new, larger seq; `deleted: true` stores a tombstone that `listItems` returns with `deleted: true`; a batch of 201 items is `400 too_many_items`; a sealed string of 262,145 characters is `413 too_large`, exactly 262,144 is accepted; a malformed id, a non-base64url sealed value, or a duplicate id inside one batch makes the whole call fail with 400 and `state().seq` unchanged (nothing written); more than `itemsTotal` (inject a limit of 5) is `409 mirror_full`; a browser token is 403.
  - `listItems`: `since=0` returns everything in seq order; `since=k` only later ones; `limit=2` over 5 items gives 2 items and `more: true`, then continuing from the last seq gives the rest with `more: false`; when each sealed value is 500,000 characters, one page holds a single item (soft byte cap, but never empty); `limit` outside 1..200 is clamped; both roles may read.
  - `lastSeen` updates at most once per 60 clock seconds per device.
  - Rate limit: with `limits: {rates: {...LIMITS.rates, itemsPut: [2, 60]}}`, the third put inside a minute is `429 rate_limited` with `retryAfter` between 1 and 60, and the window resets after 60 seconds.
- [ ] **Step 2: Run** `npm --prefix worker test` -> FAIL.
- [ ] **Step 3: Implement** `limits.js`, `sql.js`, `rate.js` and `store.js` as specified. `putItems` validates everything first, then writes in one `sql.transaction`. Auth compares `sha256Hex(token)` with the stored hash via `timingSafeEqualHex`; every method authenticates before it does anything else.
- [ ] **Step 4: Run** `npm --prefix worker test` -> PASS.
- [ ] **Step 5: Commit** `feat(mirror): MirrorStore (devices, sealed items, rate counters)`.

---

### Task 4: GateStore (pairing slots, IP rates)

**Files:**
- Create: `worker/src/gate.js`, `worker/test/gate.test.js`

**Interfaces:**
- Consumes: `Sql`, `checkRate`, `ensureRatesTable`, `LIMITS`, `randomId`, `isB64url`.
- Produces: `class GateStore { constructor(sql: Sql, opts?: {now?, limits?}); init(): void; rate(key: string, limit: number, windowSec: number): Result; startPairing(): {ok: true, pairId: string, expiresAt: number}; joinPairing(pairId: string, phonePub: string): Result; replyPairing(pairId: string, sealed: string): Result; getPairing(pairId: string): {ok: true, state: "waiting" | "joined" | "replied" | "cancelled", phonePub?: string, sealed?: string} | {ok: false, status, error}; cancelPairing(pairId: string): Result }`. Table `slots(pairId TEXT PRIMARY KEY, state TEXT, phonePub TEXT, sealed TEXT, expiresAt INTEGER)`. `phonePub` is a 65-byte uncompressed P-256 point as base64url, so exactly 87 characters; `sealed` is at most 4,096 characters. Slot lifetime is `LIMITS.pairTtlSec` from creation; a slot is live while `now <= expiresAt`.

- [ ] **Step 1: Write failing tests** in `gate.test.js`: happy path (`startPairing` -> `getPairing` waiting -> `joinPairing` -> `getPairing` joined with the same `phonePub` -> `replyPairing` -> `getPairing` replied with the exact `sealed` -> a second `getPairing` is `404 not_found` because a reply is read once); second `joinPairing` is `409 slot_taken`; `replyPairing` before join is `409 wrong_state`; second reply is `409 wrong_state`; `phonePub` of 86 or 88 characters, or containing `=`, is `400 bad_request`; `sealed` over 4,096 is `413 too_large`; clock boundary: at `expiresAt` the slot is live, one second later `getPairing`/`joinPairing`/`replyPairing` are `410 gone` and the slot is deleted; `cancelPairing` makes `getPairing` return state `cancelled` until expiry and blocks join and reply with `409 wrong_state`; unknown or malformed pair id is `404 not_found`; `startPairing` removes expired slots (count rows afterwards); `rate("ip1", 3, 600)` allows 3 then rejects with `retryAfter`, a different key is independent, and the window resets after 600 seconds; pair ids are distinct across 1000 starts and 22 characters long.
- [ ] **Step 2: Run** -> FAIL.
- [ ] **Step 3: Implement** `GateStore` with `ensureRatesTable` shared from `rate.js`.
- [ ] **Step 4: Run** -> PASS.
- [ ] **Step 5: Commit** `feat(mirror): GateStore (pairing slots, IP rate counters)`.

---

### Task 5: The router

**Files:**
- Create: `worker/src/router.js`, `worker/test/support/memory-backend.js`, `worker/test/router.test.js`

**Interfaces:**
- Consumes: `GateStore`, `MirrorStore`, `LIMITS`, auth helpers.
- Produces:
  - Backend interface (all methods may be async): `backend.gate` with `rate, startPairing, joinPairing, replyPairing, getPairing, cancelPairing`; `backend.createMirror({deviceId, ownerTokenHash}): Promise<{ok: true, mirrorId: string} | {ok: false, status, error}>`; `backend.mirror(mirrorId: string)` returning an object with `addDevice, listDevices, removeDevice, putItems, listItems, state` (the `MirrorStore` signatures).
  - `handleApi(request: Request, backend, opts?: {now?: () => number}): Promise<Response>`.
  - `memory-backend.js` (test support): `makeMemoryBackend(opts?)` building a real `GateStore` and a `Map` of `MirrorStore`s over `node:sqlite`, with an injectable clock; `createMirror` generates `randomId()`.
- Routes and bodies (JSON; `Content-Type: application/json`; every response has `Cache-Control: no-store`):

| Route | Body -> success |
|---|---|
| `POST /api/mirrors` | `{deviceId, ownerTokenHash}` -> 201 `{mirrorId, deviceId}`; rate key `mirrors:<ipHash>` |
| `POST /api/pair/start` | none -> 201 `{pairId, expiresAt}`; rate `pairStart` |
| `GET /api/pair/<id>` | -> 200 `{state, phonePub?, sealed?}`; rate `pairPoll` |
| `POST /api/pair/<id>/join` | `{phonePub}` -> 200 `{}`; rate `pairJoin` |
| `POST /api/pair/<id>/reply` | `{sealed}` -> 200 `{}` |
| `POST /api/pair/<id>/cancel` | none -> 200 `{}` |
| `POST /api/m/<mirrorId>/devices` | `{deviceId, tokenHash}` -> 201 `{}`; `GET` -> `{devices}`; `DELETE /api/m/<mirrorId>/devices/<deviceId>` -> 200 `{}` |
| `PUT /api/m/<mirrorId>/items` | `{items}` -> 200 `{seq}` |
| `GET /api/m/<mirrorId>/items?since=&limit=` | -> `{items, seq, more}` |
| `GET /api/m/<mirrorId>/state` | -> `{seq}` |

  `ipHash` is `sha256Hex(request.headers.get("CF-Connecting-IP") ?? "unknown")`. Ids in paths must be `isB64url(id, 22, 22)` for pair and mirror ids, else 404 without touching the backend.

- [ ] **Step 1: Write failing tests** in `router.test.js` using `new Request("https://x.test/api/...")` against `makeMemoryBackend()`:
  - End-to-end flow: phone `POST /api/mirrors` -> 201; phone registers a browser device; phone `PUT` 3 items; browser `GET items?since=0` returns them with seqs 1..3; owner `DELETE` the browser; the browser's next `GET` is 401.
  - End-to-end pairing flow: start, poll (waiting), join, poll (joined with `phonePub`), reply, poll (replied with `sealed`), poll again 404.
  - Unknown route 404 `{"error":"not_found"}`; `GET /api/mirrors` is 405 `method_not_allowed`; invalid JSON body is 400; a body of exactly 1,048,576 bytes is not rejected as too large (whatever validation then says), 1,048,577 bytes is 413 `too_large` (checked from `Content-Length` and from the actual text); `/api/m/<21 chars>/state`, `/api/m/../state` and `/api/m/%2e%2e/state` are 404; missing `Authorization` is 401; an `Authorization` header of 10,000 characters or with unicode is 401 and never throws.
  - Rate limiting: the 6th `POST /api/mirrors` from one `CF-Connecting-IP` inside an hour is 429 with a numeric `Retry-After`; another IP is unaffected.
  - No response carries any `Access-Control-*` header; every response has `Cache-Control: no-store` and an `application/json` content type.
  - Failures from the stores keep their status and `{"error": code}` unchanged (for example 409 `slot_taken` on a second join).
- [ ] **Step 2: Run** -> FAIL.
- [ ] **Step 3: Implement** `router.js` as a small route table (method + path pattern -> handler); read the body once as text, enforce the cap, `JSON.parse` inside a try block; all unexpected exceptions become 500 `{"error":"internal"}` without echoing the message.
- [ ] **Step 4: Run** -> PASS.
- [ ] **Step 5: Commit** `feat(mirror): REST router`.

---

### Task 6: Durable Objects, entry point, wrangler config

**Files:**
- Create: `worker/src/entry.js`, `worker/src/do.js`, `worker/test/entry.test.js`
- Modify: `worker/src/worker.js` (replace the placeholder), `worker/wrangler.toml`

**Interfaces:**
- Consumes: `handleApi`, `GateStore`, `MirrorStore`, `durableSql`, `randomId`.
- Produces:
  - `entry.js`: `makeFetch(getBackend: (env) => Backend): (request: Request, env: {ASSETS: {fetch(request): Promise<Response>}}) => Promise<Response>`. Paths `/api` and `/api/...` go to `handleApi(request, getBackend(env))`; everything else to `env.ASSETS.fetch(request)`.
  - `do.js`: `export class Gate extends DurableObject` and `export class Mirror extends DurableObject` (from `cloudflare:workers`), each building its store in the constructor from `durableSql(ctx.storage)` and calling `init()`; their public methods forward to the store (Gate: the `GateStore` methods; Mirror: `create` plus the `MirrorStore` methods); `export function doBackend(env)` implementing the backend interface: `gate` is `env.GATE.getByName("gate")`, `createMirror` generates `mirrorId = randomId()` and calls `env.MIRROR.getByName(mirrorId).create(...)`, `mirror(id)` returns `env.MIRROR.getByName(id)`.
  - `worker.js`: `import { doBackend, Gate, Mirror } from "./do.js"; export { Gate, Mirror }; export default { fetch: makeFetch(doBackend) }`.
  - `wrangler.toml` additions: durable object bindings `MIRROR` (class `Mirror`) and `GATE` (class `Gate`), and `[[migrations]] tag = "v1"`, `new_sqlite_classes = ["Mirror", "Gate"]`.

- [ ] **Step 1: Write failing tests** in `entry.test.js` (imports `entry.js` only, never `do.js`): `/api/state-nope` reaches the router (a 404 JSON body); `/` and `/index.html` call the stub `ASSETS.fetch` once each and return its response; `/apix` and `/api2/x` go to ASSETS, not the router; the stub backend factory is called with `env`.
- [ ] **Step 2: Run** -> FAIL.
- [ ] **Step 3: Implement** the four files and the toml additions.
- [ ] **Step 4: Run** `npm --prefix worker test` -> PASS, and `npm --prefix worker run check` -> exits 0 (the dry-run bundles `do.js`, so a wrong import fails here).
- [ ] **Step 5: Commit** `feat(mirror): Durable Object classes, entry point, wrangler bindings`.

---

### Task 7: Deploy workflow, smoke test, setup docs

**Files:**
- Create: `worker/scripts/smoke.mjs`, `docs/features/mirroring.md`
- Modify: `.github/workflows/mirror.yml` (add the `deploy` job)

**Interfaces:**
- Produces: `node worker/scripts/smoke.mjs <baseUrl>` exits 0 only if every check passes and prints one line per check; the deploy job exports the deployed URL to the smoke test.

- [ ] **Step 1: Write `smoke.mjs`** (Node `fetch`, no dependencies). Checks in order, each failing the script with a clear message: `GET /` is 200 and its `content-security-policy` header contains `frame-ancestors 'none'`; `POST /api/mirrors` with a random 22-character `deviceId` and a random 64-hex `ownerTokenHash` is 201; `PUT items` with one item (random id, sealed `"AAAA"`) is 200 with `seq` 1; `GET items?since=0` returns that item; the same request with a wrong token is 401; `POST /api/pair/start` is 201, `POST /api/pair/<id>/join` with an 87-character `phonePub` is 200, `GET` shows `joined`, `POST cancel` then `GET` shows `cancelled`; no response has an `access-control-allow-origin` header.
- [ ] **Step 2: Add the `deploy` job** to `mirror.yml`: `needs: test`, runs only on `push` to `main` or `workflow_dispatch`; job env `HAS_CF: ${{ secrets.CLOUDFLARE_API_TOKEN != '' && secrets.CLOUDFLARE_ACCOUNT_ID != '' }}`; every step after checkout carries `if: env.HAS_CF == 'true'` (like the iOS workflow's `HAS_KEY`), so a repo without the secrets passes with the deploy skipped; steps: checkout, setup-node 22, `npm ci` in `worker`, `npm --prefix web run build`, `npx wrangler deploy 2>&1 | tee deploy.log` in `worker` with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from secrets, extract the first `https://...workers.dev` URL from `deploy.log` (fail if none), run the smoke script with it, and print the URL in the job summary.
- [ ] **Step 3: Write `docs/features/mirroring.md`**: what Mirroring is (one paragraph from the spec's Intent), **Setup (once)** as numbered steps (create a free Cloudflare account; create an API token from the "Edit Cloudflare Workers" template; copy the account id; add both as repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the GitHub website; run the "Mirror" workflow by hand; the deployed address is in the run summary), the API table and limits from this plan, the trust model paragraph from the spec, and a "Not verified by CI" note (workerd behaviour is only checked by the smoke test on deploy). Add one line to `AGENTS.md` under Layout: `worker/` and `web/` hold Mirroring's Worker and web app (see `docs/features/mirroring.md`).
- [ ] **Step 4: Verify locally** that the smoke script's logic runs against a local stand-in: write `worker/test/smoke.test.js` which starts `http.createServer` adapting `makeFetch` with the memory backend and a stub `ASSETS` (serving the CSP header), runs `smoke.mjs` as a child process against it, and asserts exit code 0. Run `npm --prefix worker test` -> PASS.
- [ ] **Step 5: Push and check CI.** Push to `main`; read the `Mirror` run with `gh run view`; the `test` job must be green and `deploy` green or skipped. Report plainly: with no secrets the deploy and smoke test did not run, so the Durable Object glue is verified only by `wrangler --dry-run` until the person adds the secrets.
- [ ] **Step 6: Commit** `feat(mirror): deploy workflow, smoke test, setup docs`.

---

## Self-review (against the spec)

- Cloudflare side, Gate and Mirror objects: Tasks 3, 4, 6. Endpoint table: Task 5 (all rows except mailbox and live channel, which the spec assigns to phases 4 and 5). Limits and no-plaintext logging: Global Constraints, Tasks 3 and 5. Static assets with strict CSP: Tasks 1 and 7. Deploy with secrets and the smoke test: Task 7.
- Names are consistent across tasks: `MirrorStore`, `GateStore`, `makeMemoryBackend`, `handleApi`, `makeFetch`, `doBackend`, `LIMITS`, `checkRate`.
- Deliberately not here: sealing/crypto (phase 2 plan), the mailbox and live socket (later phases), key rotation (hardening).
