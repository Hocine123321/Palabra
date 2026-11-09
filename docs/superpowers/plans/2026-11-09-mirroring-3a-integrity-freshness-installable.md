# Mirroring, plan 3a: integrity check, freshness badge, installable offline app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The page can tell a complete, current copy from a withheld, partial or replayed one; it shows how fresh the phone's data is; and it installs as an app and opens offline.

**Architecture:** The phone seals one more item, the **manifest** (counts per kind, a hash of all item ids, `pushedAt`), after the data items of every sync that needs one. The page opens it with the same code as any item and compares it to its local copy. Item generations come from the clock so a lost index file can never make them go backwards. A hand-written service worker precaches the shell under a build-hash name; it never touches `/api/*`.

**Tech Stack:** Swift/CryptoKit/XCTest + `MockURLProtocol` (iOS 17); web: plain ES modules, WebCrypto, IndexedDB (`fake-indexeddb` in tests), `esbuild`, `node:vm` for service-worker tests, Python `cryptography` for the independent vector check; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-07-mirroring-design.md` (Keys and sealing: manifest; The web app: service worker; Phase 3). **Builds on:** plans 1 and 2 (`docs/superpowers/plans/2026-11-07-mirroring-*.md`, all shipped).

**Split of phase 3:** this plan is 3a. Plan 3b (not written yet): the other collections (decks and due counts, Need Review, stats, Artifact pages, latest chat, Books lessons) pushed and shown. Plan 3c: revoke with `dataKey` rotation. The manifest here is generic over kinds, so 3b needs no change to it.

## Global Constraints

- **Manifest item (Protocol v1 addition, additive):** kind `"manifest"`, recordId `"manifest"`, item id derived like any item. Payload `d` = `{"counts":{"<kind>":<integer >= 1>},"idsHash":"<64 lowercase hex>","pushedAt":"<ISO-8601 UTC, whole seconds, e.g. 2026-11-09T21:30:00Z>"}`. Envelope `g` follows the generation rule below.
- **`idsHash`** = lowercase hex SHA-256 of the UTF-8 text made of the item ids of every live item **except the manifest**, sorted in code-point order and joined with `"\n"` (no trailing newline; an empty list hashes the empty string). `counts` has one entry per kind with at least one live item, manifest excluded. Items the phone skipped as too large are not in the index, so they are in neither.
- **Generation:** a push's `g` = `max(index.generation + 1, whole seconds since 1970-01-01 UTC)`. The browser keeps the rule from plan 2: a row never replaces a row with a higher `g`.
- **Manifest timing:** pushed after the data items, in its own request, when the push sent or deleted anything, or the computed `idsHash` differs from the last manifest's, or none was pushed in the last 600 seconds (`MirrorManifest.heartbeat`), or none was ever pushed.
- **Page states:** `verified` (valid manifest, counts and `idsHash` equal the local copy), `incomplete` (valid manifest, they differ), `unverified` (no manifest, or one that fails validation). **Refused, never applied:** a pull whose first page reports a head `seq` lower than the saved `lastSeq`, or that carries a manifest with `g` lower than the saved manifest's (`RollbackDetected`).
- Service worker: scope `/`, shell cache name `palabra-shell-<12 hex of the build hash>`, never handles `/api/*`, non-GET or cross-origin requests. Shell = `/`, `/app.js`, `/app.css`, `/manifest.webmanifest`, `/icons/icon-192.png`, `/icons/icon-512.png`.
- Installable: `manifest.webmanifest` with `name` "Palabra", `short_name` "Palabra", `start_url` "/", `scope` "/", `display` "standalone", `background_color` "#fcfbf8", `theme_color` "#d97757", icons 192 and 512 (purpose any) and 512 (purpose maskable), made from `Palabra/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
- Existing rules hold: strict CSP (`web/public/_headers`, no inline script or style), no `innerHTML`, every new UI string has an Arabic entry in `web/src/strings.js` (and Swift strings in `ar.lproj` plus `LocalizationTests`), `Features/Mirroring` imports no `Word/Deck/Card/ReviewNeed`, no direct `withAnimation`/`.animation`, no secret in any log or request.
- Not in this plan: other collections, rotation on revoke, mailbox, live channel, a custom domain.
- After any Swift change say plainly: compiled by eye only until a real CI run.

## Review Focus

- The server withholds one item, drops a tombstone, or a page of items fails to open: the page says `incomplete`, never `verified`, and keeps showing its saved copy (Task 3).
- The server answers with older data (lower head `seq`, or an older manifest): nothing is applied, the banner says so, the saved copy is intact (Task 3).
- The phone dies between the data items and the manifest, or the index file is lost: the next sync still sends a fresh manifest, and the browser still accepts the new data because the generation only goes up (Task 2).
- A phone without manifest support (plan 2 data) or a manifest with garbage fields (`counts` a string, `idsHash` wrong length, `pushedAt` unparseable or in the future): `unverified`/no time shown, no exception, no "Invalid Date" (Tasks 1, 4).
- A new deploy while the old shell is cached, a failed service-worker registration, an offline first load: the app still opens, API calls are never cached, old caches are deleted (Task 5).

---

## File structure

```
docs/features/mirroring.md                              Protocol v1: manifest, generation; Installable app
PalabraTests/Mirroring/Fixtures/mirror-vectors.json     + "manifest" vector (generated)
web/scripts/make-vectors.mjs  verify-vectors.py         + manifest vector / check
web/src/manifest.js                                     idsHash, parseManifest, checkCopy
web/src/schedule.js                                     refreshDelay
web/src/localdb.js  sync.js  view.js  strings.js  main.js   changed
web/src/sw.js                                           service worker template
web/scripts/build.mjs  make-icons.py  e2e-local.mjs     build (sw + manifest), icon generator, local browser check
web/public/manifest.webmanifest  icons/*.png  index.html  _headers
web/test/manifest.test.js schedule.test.js sw.test.js build.test.js (+ sync/localdb/view tests)
Palabra/Features/Mirroring/Sync/MirrorManifest.swift  MirrorPusher.swift  MirrorService.swift
Palabra/Features/Mirroring/Storage/MirrorIndex.swift  MirrorSettings.swift
PalabraTests/Mirroring/MirrorManifestTests.swift  MirrorPusherTests.swift  MirrorServiceTests.swift  MirrorIndexTests.swift  MirrorStorageTests.swift
```

---

### Task 1: Manifest protocol, shared vector, JavaScript side

**Files:**
- Modify: `docs/features/mirroring.md` (Protocol v1: manifest item, `idsHash`, generation rule, page states, from Global Constraints), `web/scripts/make-vectors.mjs`, `web/scripts/verify-vectors.py`, `PalabraTests/Mirroring/Fixtures/mirror-vectors.json` (regenerated, never hand-edited)
- Create: `web/src/manifest.js`, `web/test/manifest.test.js`

**Interfaces:**
- Produces (`manifest.js`):
  - `MANIFEST_KIND = "manifest"`, `MANIFEST_RECORD = "manifest"`
  - `idsHash(ids: string[]): Promise<string>`
  - `parseManifest(row: {kind, g, d}): {generation: number, counts: Record<string, number>, idsHash: string, pushedAt: number | null} | null` (`pushedAt` in ms; `null` if unparseable or more than 5 minutes in the future; whole result `null` if `kind` is not manifest, `counts` is not an object of integers >= 1 (up to 10,000,000), or `idsHash` is not 64 lowercase hex)
  - `checkCopy(rows: {id, kind, g, d}[]): Promise<{state: "verified" | "incomplete" | "unverified", generation: number | null, pushedAt: number | null}>` (compares against all rows of kinds other than manifest; uses the manifest row with the highest `g`)
- Vector JSON gains `manifest: { ids: string[], idsHashHex: string }` with at least 4 ids that sort differently from insertion order and include `-` and `_` characters, plus `empty: { idsHashHex }` (hash of the empty string).

- [ ] **Step 1: Extend `make-vectors.mjs`** to write the `manifest` vector (Node `createHash`, ids listed unsorted in the file, expected hash over the sorted list). Run it; `git diff` shows only the added key.
- [ ] **Step 2: Extend `verify-vectors.py`** to recompute `idsHashHex` and the empty hash with `hashlib` (sorting with Python's default string sort) and exit non-zero on mismatch. Run `python3 web/scripts/verify-vectors.py` -> `OK`.
- [ ] **Step 3: Write `web/test/manifest.test.js` (RED)** using the vector file: `idsHash(ids)` equals `manifest.idsHashHex` whatever the order of `ids`; `idsHash([])` equals the empty hash. `parseManifest` accepts a good row and returns `pushedAt` in ms; returns `null` for each of: `counts` a string, a count of `0`, a count of `1.5`, `idsHash` of 63 characters, `idsHash` uppercase, `d` missing; returns `pushedAt: null` for `"banana"` and for a time one hour in the future. `checkCopy`: rows = 3 words + 1 deck + a matching manifest -> `verified` with the manifest's `generation` and `pushedAt`; remove one word -> `incomplete`; add a stray row -> `incomplete`; no manifest row -> `unverified` with `generation: null`; a garbage manifest -> `unverified`; two manifests -> the higher `g` decides. Run `npm --prefix web test` -> new tests fail.
- [ ] **Step 4: Implement `manifest.js`** (WebCrypto `crypto.subtle.digest`; hex via a local helper; no new dependency). Run tests -> all pass.
- [ ] **Step 5: Docs.** Add the manifest and generation rules to "Protocol v1" in `docs/features/mirroring.md` word for word from Global Constraints. Commit `feat(mirror): manifest protocol, shared vector and checker`.

### Task 2: Phone pushes the manifest, clock-based generations

**Files:**
- Create: `Palabra/Features/Mirroring/Sync/MirrorManifest.swift`, `PalabraTests/Mirroring/MirrorManifestTests.swift`
- Modify: `Palabra/Features/Mirroring/Sync/MirrorPusher.swift`, `MirrorService.swift`, `Palabra/Features/Mirroring/Storage/MirrorIndex.swift`, `MirrorSettings.swift`, `PalabraTests/Mirroring/MirrorVectors` usage in `MirrorCryptoTests.swift` (add `manifest`/`empty` fields to `MirrorVectors`), `MirrorPusherTests.swift`, `MirrorServiceTests.swift`, `MirrorIndexTests.swift`, `MirrorStorageTests.swift`

**Interfaces:**
- Consumes: `MirrorPusher.push(_:kinds:) async throws -> MirrorPushResult`, `MirrorRecord(kind:recordID:payload:)`, `MirrorIndex`, `MirrorSettingsStore`, the shared vector file.
- Produces:
  - `MirrorManifest` (enum): `static let kind = "manifest"`, `static let recordID = "manifest"`, `static let heartbeat: TimeInterval = 600`, `static func idsHash(_ ids: [String]) -> String`, `static func record(ids: [String], counts: [String: Int], now: Date) -> MirrorRecord`
  - `MirrorIndex`: `func itemIDs(excludingKind kind: String) -> [String]` (sorted), `func counts(excludingKind kind: String) -> [String: Int]`
  - `MirrorSettings`: `var lastManifestAt: Date?`, `var lastManifestIDsHash: String?` (tolerant decoder; missing keys decode as `nil`)
  - `MirrorPusher`: new `var now: () -> Date = Date.init` stored property (memberwise default); the generation of a push becomes `max(index.generation + 1, Int(now().timeIntervalSince1970))`

- [ ] **Step 1: Write failing tests.**
  - `MirrorManifestTests`: `testIDsHashMatchesTheSharedVector` (unsorted `ids` from the vector -> `idsHashHex`; `[]` -> empty hash); `testRecordHasKindRecordIDAndPayload` (kind/recordID constants; payload object has exactly `counts`, `idsHash`, `pushedAt`; `pushedAt` equals `"2026-11-09T21:30:00Z"` for `Date(timeIntervalSince1970: 1_794_259_800)`; check the string is ISO-8601 UTC without fractions).
  - `MirrorIndexTests`: `testIDsAndCountsExcludeAKind` (three words, one manifest -> excluding "manifest" gives the 3 sorted ids and `["word": 3]`; a kind with no items is absent from counts).
  - `MirrorStorageTests`: settings stored without the two new keys decode with both `nil`; round trip keeps them.
  - `MirrorPusherTests` (`makePusher` passes `now: { Date(timeIntervalSince1970: 0) }` so existing `g` assertions of 1 and 2 stay): `testGenerationNeverGoesBackwardsAfterTheIndexIsLost` (push with `now` = 1000 -> `g` >= 1000 in the opened envelope; new empty `MirrorIndex`, `now` = 1001, a changed record -> `g` > the first `g`); `testTwoPushesInTheSameSecondStillIncrease` (`now` fixed at 1000 -> `g` 1000 then 1001).
  - `MirrorServiceTests` (update existing expectations, then add): a first sync sends **two** PUTs, items then manifest; open the second request's single item with the vector key and assert kind `"manifest"`, `d.counts == ["word": 1]`, `d.idsHash` equals `MirrorManifest.idsHash` of the one item id, `d.pushedAt` equals the clock as ISO-8601. Add `testManifestIsSkippedWhenNothingChangedUntilTheHeartbeat` (forced sync with the same records at +5 s -> no PUT, `lastSyncAt` moves; at +601 s -> exactly one PUT whose item is the manifest), `testAFailedManifestIsRetriedNextSync` (second PUT answers 500 -> `lastError == .other`, `lastManifestIDsHash` unchanged; next forced sync sends only a manifest), `testNoRecordsStillGetsAnEmptyManifestOnce` (paired, zero records: one PUT, manifest with `counts == [:]` and the empty `idsHash`).
  Run `bash scripts/check-conventions.sh`; the Swift tests only run in CI.
- [ ] **Step 2: Implement** `MirrorManifest` (CryptoKit SHA-256, sort with `sorted()`, ISO-8601 via `ISO8601DateFormatter` with `[.withInternetDateTime]`), the two `MirrorIndex` helpers, the two settings fields, the `now` property and generation rule in `MirrorPusher`, and in `MirrorService.sync`: after a successful items push compute `ids`/`counts` from the index, decide "due" by the Global Constraints rule, push `[MirrorManifest.record(...)]` with `kinds: [MirrorManifest.kind]` through the same pusher (constructed with `now: now`), then store `lastManifestAt` and `lastManifestIDsHash` in settings. A failure in the manifest push sets `lastError` like any other and leaves the two fields unchanged. `turnOffAndForget` already resets settings.
- [ ] **Step 3: Verify and commit.** `bash scripts/check-conventions.sh`, then `git commit -m "feat(mirror): sealed manifest after each sync, clock-based generations"`.

### Task 3: The page checks its copy and refuses replays

**Files:**
- Modify: `web/src/localdb.js`, `web/src/sync.js`, `web/test/localdb.test.js`, `web/test/sync.test.js`

**Interfaces:**
- Consumes: `checkCopy`, `MANIFEST_KIND` (Task 1); `openRow`'s row shape `{id, kind, recordId, g, d}`.
- Produces:
  - `db.allItems(): Promise<Row[]>`, `db.getMeta(key: string): Promise<any>`, `db.setMeta(key: string, value: any): Promise<void>` (`clearAll` clears meta as before)
  - `class RollbackDetected extends Error` with `reason: "seq" | "generation"`, exported from `sync.js`
  - `pullOnce(...)` result gains `check: {state, generation, pushedAt}` (from `checkCopy(await db.allItems())` after the last page)
  - `describeCopy(db): Promise<{state, generation, pushedAt}>` exported from `sync.js` (used for the saved copy on load)

- [ ] **Step 1: Write failing tests** (`sync.test.js` with the existing `setup/sealed/fakeApi` helpers; add a `manifestFor(keys, rows, g, pushedAt)` helper that seals a correct manifest using `idsHash`):
  - `a complete pull with a matching manifest is verified` (3 words + manifest; `check.state === "verified"`, `check.generation` = manifest `g`, `check.pushedAt` = its time)
  - `a missing item makes the check incomplete, the rows that did arrive are kept` (manifest lists 3, server serves 2)
  - `a tombstone the server dropped leaves a stale row and is incomplete` (manifest lists 2 live ids; local copy has 3 because the delete never arrived)
  - `an unopenable item (tampered seal) makes the copy incomplete and is counted as rejected`
  - `no manifest -> unverified, words still stored`
  - `a head seq lower than the saved lastSeq throws RollbackDetected("seq") and changes nothing` (save `lastSeq` 10 and 3 rows; api returns `seq: 4`; rows and `lastSeq` unchanged)
  - `a manifest older than the saved one throws RollbackDetected("generation") and the saved manifest and words are unchanged` (saved manifest `g` 9; page carries manifest `g` 8 plus a changed word; the word is **not** applied)
  - `a newer manifest after a rollback attempt is accepted again` (same db: next pull with `g` 10 works)
  `localdb.test.js`: `allItems returns every row of every kind`, `getMeta/setMeta round-trip and clearAll empties meta`. Run -> fail.
- [ ] **Step 2: Implement.** `localdb.js`: the three methods (no schema bump). `sync.js`: before the loop read the saved manifest (`itemsByKind("manifest")`, highest `g`) and `since`; in the loop throw `RollbackDetected("seq")` when the first page's `seq < since`, and `RollbackDetected("generation")` (before `applyPage` for that page) when a page contains a manifest row with `g` below the saved manifest's `g`; after the loop compute `check`. `AuthRevoked` handling unchanged.
- [ ] **Step 3: Run** `npm --prefix web test` -> all pass (46 existing + new). Commit `feat(web): verify the local copy against the manifest, refuse replayed state`.

### Task 4: Freshness badge and retry timing

**Files:**
- Create: `web/src/schedule.js`, `web/test/schedule.test.js`
- Modify: `web/src/view.js`, `web/src/strings.js`, `web/src/main.js`, `web/src/app.css`, `web/test/view.test.js`

**Interfaces:**
- Consumes: `describeCopy`, `RollbackDetected`, `pullOnce(...).check` (Task 3).
- Produces:
  - `refreshDelay({state: string | null, incompleteRuns: number}): number` in `schedule.js`: `10_000` when `state === "incomplete"` and `incompleteRuns < 6`, otherwise `60_000`
  - `wordsScreen({words, syncedAt, status, freshness, lang, onRefresh}, tr)` where `freshness = {state: "verified" | "incomplete" | "unverified", pushedAt: number | null, rollback: boolean}`; `status` also accepts `"rollback"`

- [ ] **Step 1: Write failing tests.** `schedule.test.js`: the four cases (incomplete runs 0 and 5 -> 10,000; incomplete run 6 -> 60,000; verified/unverified/null -> 60,000). `view.test.js` (uses the existing fake DOM `mount` helper): with `freshness.verified` and `pushedAt` the screen text contains "Phone synced" and the formatted time and no "Invalid Date"; `pushedAt: null` -> no time and no "Phone synced"; `incomplete` -> "Still receiving from your phone…"; `unverified` -> "Not verified yet"; `pushedAt` older than 24 h (with a `now` passed via a new optional `now: () => number` prop defaulting to `Date.now`) -> the "may be out of date" line; `rollback: true` -> the rollback banner with `role="alert"`; a Spanish word `"<img src=x onerror=alert(1)>"` still appears only as a text node in all states; every new English string has an Arabic entry in `KEYS` (extend the existing KEYS coverage test, or add one that loads every `tr("…")` literal from `view.js`).
  New strings (English as key): "Phone synced", "Still receiving from your phone…", "Not verified yet", "The phone has not synced for over a day, so this may be out of date.", "The server sent older data than this computer already has, so it was ignored. Showing your saved copy." Write Arabic for each.
- [ ] **Step 2: Run -> fail. Step 3: Implement** `schedule.js`, the view changes (the new lines sit under the existing "Last updated" line; CSS only with the existing tokens, a `.stale` class for the old-data line), and `main.js`: `draw()` calls `describeCopy(db)`; `refresh()` catches `RollbackDetected` (sets `status = "rollback"`, keeps the copy), keeps the `check` from `pullOnce`, counts consecutive `incomplete` runs, and schedules the next refresh with `refreshDelay` (replace the fixed `setInterval` with a self-rescheduling timeout tied to `screenToken`).
- [ ] **Step 4: Run** `npm --prefix web test` and `node web/scripts/build.mjs` -> pass, no error. Commit `feat(web): freshness badge, incomplete and rollback states, retry timing`.

### Task 5: Installable app and service worker

**Files:**
- Create: `web/src/sw.js`, `web/public/manifest.webmanifest`, `web/public/icons/icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `web/scripts/make-icons.py`, `web/test/sw.test.js`
- Modify: `web/scripts/build.mjs`, `web/public/index.html`, `web/public/_headers`, `web/src/main.js`, `web/test/build.test.js`, `docs/features/mirroring.md` ("Installing the web app")

**Interfaces:**
- Produces: `dist/sw.js` (template `src/sw.js` with `__VERSION__` and `__SHELL__` (a JSON array) replaced by `build.mjs`); version = first 12 hex of SHA-256 over the bytes of every shell file in the fixed shell order. `sw.js` is a classic script (no imports) that registers `install`, `activate` and `fetch` listeners on `self`.

- [ ] **Step 1: Write failing tests.**
  - `sw.test.js` loads `src/sw.js`, substitutes the placeholders, runs it in `node:vm` with a fake `self` (collects listeners; `skipWaiting`, `clients.claim` stubs), an in-memory `caches` (`open/keys/delete/match`), `Response`, `URL`, and a controllable `fetch`: `install precaches the whole shell under palabra-shell-<version> and skips waiting`; `activate deletes older palabra-shell caches and keeps other names and the current one`; `fetch never answers /api/ requests, non-GET requests or other origins` (`respondWith` not called); `a cached asset is served without the network`; `a navigation goes to the network first and falls back to the cached "/" when offline`; `an uncached asset that fails offline rejects (no invented response)`; `a successful navigation response refreshes the cached "/"`.
  - `build.test.js`: `dist/sw.js` has no `__VERSION__` or `__SHELL__`; every shell path exists in `dist`; building twice gives the same version; changing a byte of `app.css` gives a different one (run the build against a temp copy of `web/src/app.css`, or assert through the exported `versionFor(files)` helper if `build.mjs` exports it); `manifest.webmanifest` parses and has every field from Global Constraints; each icon file exists and is a PNG with exactly the declared size (read the width/height from the IHDR bytes); `index.html` links the manifest, `theme-color` `#d97757`, and an `apple-touch-icon`; `_headers` contains a `/sw.js` section with `Cache-Control: no-cache`; the CSP still has `worker-src 'self'` and `manifest-src 'self'`.
- [ ] **Step 2: Run -> fail. Step 3: Implement.** `make-icons.py` (Pillow, run once by hand, output committed) resizes the 1024 app icon to the three PNGs. `sw.js` behaviour exactly as the tests say; strategy: install -> `cache.addAll(shell)` then `skipWaiting`; activate -> delete stale shell caches then `clients.claim`; fetch -> ignore as listed, navigations network-first with the cached `"/"` fallback (and refresh it on success), everything else cache-first. `build.mjs`: build order unchanged, then compute the version, write `dist/sw.js`. `_headers` gets the `/sw.js` section; `index.html` the three tags; `main.js` registers the worker after `load` inside `if ("serviceWorker" in navigator)` with `.catch(() => {})`.
- [ ] **Step 4: Run** `npm --prefix web test` -> pass. View each icon once (Read the PNG) and confirm it is the app icon. Commit `feat(web): installable app and offline shell`.

### Task 6: Phase check, CI, report

**Files:**
- Create: `web/scripts/e2e-local.mjs` (the real-Chromium check, run by hand: needs `playwright`; header comment says so)
- Modify: `.github/workflows/mirror.yml` only if a step is missing (the vector check and web tests already run), `docs/features/mirroring.md` ("Not verified by CI", "Known gaps")

- [ ] **Step 1: Write `e2e-local.mjs`** from the existing local script (Worker router + memory backend + built `dist`): pair a JS phone, push 3 words **and a correct manifest** -> page shows "Phone synced"; push a manifest that lists one more id than exists -> page shows "Still receiving from your phone…" and recovers when the missing word is pushed; serve a lower `seq` -> rollback banner and the list unchanged; with the service worker registered (`localhost` counts as secure) reload with `context.setOffline(true)` -> the page still renders the words; `await page.evaluate(() => fetch("/manifest.webmanifest"))` is valid JSON. Run it locally; screenshots of the badge states at DPR 2 saved next to the old ones.
- [ ] **Step 2: Whole-repo checks.** `npm --prefix web test`, `npm --prefix worker test`, `python3 web/scripts/verify-vectors.py`, `git diff --exit-code PalabraTests/Mirroring/Fixtures/mirror-vectors.json` after rerunning `make-vectors.mjs`, `bash scripts/check-conventions.sh`.
- [ ] **Step 3: Update docs** ("Not verified by CI": camera scan, real Safari/Firefox, installing on a real PC, a real Cloudflare Worker; "Known gaps": other collections, rotation, no mailbox). Commit `docs(mirror): phase 3a notes`.
- [ ] **Step 4: Push once; read both workflows** (`gh run list`, `gh run view`): Build (ipa + tests) and Mirror must be green. Fix compile errors or failing Swift tests with RED -> GREEN, push again.
- [ ] **Step 5: Report** to the person: what changed, what the badge states mean, screenshots, what CI cannot prove (real device install, real Cloudflare), and that the Swift part was compiled by CI only after this push.
