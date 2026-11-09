# Mirroring, plan 3c: revoking a computer rotates the data key

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Removing a computer cuts it off from new data for good: the phone makes a new `dataKey`, hands it to the computers that stay, and re-encrypts everything, so the removed computer's copy of the old key opens nothing that is stored afterwards.

**Architecture:** At pairing the phone also gives each computer a random `deviceKey` (inside the sealed wrap). To rotate, the phone seals the new `dataKey` to every remaining computer under that computer's `deviceKey` and calls one atomic Worker endpoint that removes the revoked device, deletes every item, bumps an `epoch` and stores the sealed keys. Each page notices the new epoch on its next check, opens its sealed key, drops its old copy and pulls again; the phone re-pushes everything under the new key at once. The phone saves the new key as *pending* before the call and promotes it only when the Worker confirms, so a crash can never lose the key that decrypts the stored data.

**Tech Stack:** Worker: JS, SQLite Durable Object (`node:sqlite` adapter in tests); Swift/CryptoKit/XCTest; web: WebCrypto, IndexedDB; Python `cryptography` for the independent vector check.

**Spec:** `docs/superpowers/specs/2026-11-07-mirroring-design.md` (Pairing step 5; Trust model; Phase 3). **Builds on:** plans 1, 2, 3a (3b is independent).

## Global Constraints

- **Wrap v1 gains `deviceKey`:** the pairing wrap plaintext is `{"v":1,"mirrorId","deviceId","deviceToken","dataKey","deviceKey"}`, `deviceKey` = 32 random bytes, base64url. The phone stores one per computer (`MirrorComputer.deviceKey: String?`, tolerant decoder); the browser stores it as a non-extractable AES-GCM `CryptoKey` in its credentials. Computers paired before this plan have none (`nil`).
- **Rotation blob** (phone -> one browser) = `iv(12) | AES-256-GCM(deviceKey) ciphertext | tag(16)`, base64url, over UTF-8 JSON `{"v":1,"epoch":<int>,"dataKey":"<base64url 32 bytes>"}`, associated data = UTF-8 of `"palabra-mirror-rotate-v1|" + mirrorId + "|" + deviceId + "|" + epoch`. `epoch` is a positive integer, one higher than the Worker's current epoch (a mirror starts at epoch 0).
- **Worker:** `POST /api/m/<mirrorId>/rotate` (owner only; body at most 16,384 bytes): `{"epoch": <int>, "remove": "<deviceId>" | null, "blobs": {"<deviceId>": "<base64url, <= 2,048 chars>"}}`. In one transaction: requires `epoch == current + 1` (else `409 stale_epoch`); every key of `blobs` must be an existing browser device and not `remove` (else `400 bad_request`); `remove` (if any) must be an existing browser (else `404 not_found`); every browser device that is **neither** in `blobs` **nor** the removed one is also removed (they cannot learn the new key); deletes all items and sets the `bytes` meta to 0 but **never lowers `seq`**; stores `epoch` and the blobs (replacing older ones). Answer `{epoch, removed: [deviceId...]}`. `GET /api/m/<mirrorId>/state` additionally returns `epoch`. `GET /api/m/<mirrorId>/rotation` (any device) returns `{epoch, blob}` for the caller (`404` when the caller has no blob for the current epoch). Rate limit `rotate`: 6 per hour per device.
- **Phone secrets:** `MirrorSecrets` gains `epoch: Int` (default 0 when absent) and `pending: {dataKey: String, epoch: Int}?`. Promotion rule on every service start and before every sync: if `pending` exists and the Worker's state `epoch == pending.epoch` it becomes the live `dataKey`/`epoch` and `pending` is cleared; if the Worker's epoch is still the old one, `pending` is discarded.
- **Browser behaviour:** before each pull the page reads `state.epoch`. If it is higher than the saved epoch: fetch `/rotation`, open the blob with its `deviceKey` (check `epoch` inside equals the Worker's), import the new `dataKey`, replace credentials (epoch, keys), clear items and `lastSeq`, then pull. If there is no blob, or it fails to open, or the computer has no `deviceKey`, the page shows "This computer was removed" (same screen as a revoked token) and clears its copy.
- **Phone behaviour:** removing a computer (`MirrorService.remove(computerID:)`) rotates when at least one other computer remains: new `dataKey`; blobs for every remaining computer that has a `deviceKey`; remaining computers **without** a `deviceKey` are removed too and the Settings screen says which ("Paired before key rotation existed; pair it again"); when no computer remains it just deletes the device and rotates to a fresh key with no blobs. After the Worker confirms: promote the key, `index.reset()`, and run a forced sync (everything is re-pushed under the new key, then the manifest).
- Items are keyed by `HMAC(kId, ...)`, so a new key changes every item id; nothing from the old epoch is reused or migrated.
- Existing rules hold: no secret (data key, device key, token, blob) in any log, URL or error text; Arabic keys for every new string (`ar.lproj`, `strings.js`); conventions script; honest Swift status ("compiled by eye only until CI").

## Review Focus

- The phone crashes or loses network **after** the Worker rotated but **before** it saved the new key (or before the re-push): on next launch the pending key is promoted and the re-push happens; the data on the Worker is never left sealed under a key nobody holds (Task 3).
- Two rotations race (two phones, a double tap, a retry after a timeout): the second gets `409 stale_epoch`, changes nothing, and the phone re-reads the state instead of looping (Tasks 1, 3).
- A page that was offline during rotation comes back: it sees the higher epoch, rekeys, and does not show old data or half-decrypted garbage; a page without a blob shows "removed" (Task 4).
- The removed computer keeps polling with its old token: it gets `401` and its old key opens nothing now stored; a browser removed by a rotation that left it out (no `deviceKey`) is told it was removed, not stuck "incomplete" (Tasks 1, 4).
- The mirror rotates while `seq` matters: the head `seq` never goes down, so plan 3a's replay check does not false-alarm, and a page that already rekeyed does not pull the old epoch's rows (Tasks 1, 4).

---

## File structure

```
docs/features/mirroring.md                       Protocol v1: deviceKey, rotation blob, epoch; API table; Trust model
PalabraTests/Mirroring/Fixtures/mirror-vectors.json  + "rotation" vector (generated)
web/scripts/make-vectors.mjs  verify-vectors.py
worker/src/store.js  router.js  limits.js  rate.js(unchanged)    worker/test/store.test.js  router.test.js
web/src/crypto.js  api.js  pairing.js  localdb.js  sync.js  main.js  strings.js   web/test/*.test.js
Palabra/Features/Mirroring/Crypto/MirrorCrypto.swift  Net/MirrorClient.swift  Storage/MirrorSecrets.swift  Pairing/MirrorPairingSession.swift  Sync/MirrorService.swift
Palabra/Features/Settings/MirroringSettingsView.swift
PalabraTests/Mirroring/MirrorCryptoTests.swift MirrorClientTests.swift MirrorStorageTests.swift MirrorPairingSessionTests.swift MirrorServiceTests.swift
```

### Task 1: Worker `rotate`, `epoch` and `rotation`

**Files:**
- Modify: `worker/src/store.js`, `worker/src/router.js`, `worker/src/limits.js`, `worker/test/store.test.js`, `worker/test/router.test.js`, `worker/test/smoke.test.js` (if it lists endpoints), `docs/features/mirroring.md` (API table, limits)

**Interfaces:**
- Produces: `MirrorStore.rotate(bearer, {epoch, remove, blobs}): Promise<{ok:true, epoch, removed: string[]} | {ok:false, status, error}>`; `MirrorStore.rotation(bearer): Promise<{ok:true, epoch, blob} | {ok:false, status:404, error:"not_found"} | ...>`; `state()` result gains `epoch: number`; `LIMITS.rotateBodyBytes = 16384`, `LIMITS.blobChars = 2048`, `LIMITS.rates.rotate = [6, 3600]`.

- [ ] **Step 1: Write failing tests** (`store.test.js`, helpers `makeStore/addBrowser/item` as in the file): `rotate` happy path (2 browsers, remove one, blob for the other: removed device gets 401, remaining device authenticates, all items gone, `state.epoch === 1`, `seq` equals the pre-rotation `seq`, a following `putItems` returns `seq + 1`, `bytes` meta is 0); `a browser missing from blobs and not removed is removed too` (and reported in `removed`); `stale epoch` -> `409 stale_epoch` and nothing changed (items, devices); `blobs` naming the owner, an unknown device or the removed device -> 400 and nothing changed; `remove` unknown -> 404; browser token -> 403; blob longer than 2,048 chars -> 400; blob not base64url -> 400; `rotation()` returns the caller's blob for the current epoch, 404 for a device without one and after a second rotation that did not include it; rate limit 429 after 6 in the window (inject `rates: {rotate: [2, 60]}`). `router.test.js`: the three routes map to the store, `POST /rotate` over 16,384 bytes -> 413 without reading further, unauthenticated -> 401 before the body is parsed, `GET /rotation` is not cacheable (`Cache-Control: no-store`).
- [ ] **Step 2: Run `npm --prefix worker test` -> fail. Step 3: Implement** in one `sql.transaction`: add `epoch` (default 0) and a `rotation` table `(deviceId TEXT PRIMARY KEY, epoch INTEGER NOT NULL, blob TEXT NOT NULL)` created lazily in `init()`; items delete resets bytes only. **Step 4: Run all worker tests -> pass; commit** `feat(worker): atomic key rotation, epoch and per-device rotation blobs`.

### Task 2: Protocol vectors and cryptography on both sides

**Files:**
- Modify: `docs/features/mirroring.md` (Protocol v1: `deviceKey`, rotation blob, epoch), `web/scripts/make-vectors.mjs`, `web/scripts/verify-vectors.py`, `PalabraTests/Mirroring/Fixtures/mirror-vectors.json` (regenerated), `web/src/crypto.js`, `web/test/crypto.test.js`, `Palabra/Features/Mirroring/Crypto/MirrorCrypto.swift`, `PalabraTests/Mirroring/MirrorCryptoTests.swift`

**Interfaces:**
- Produces (web): `importDeviceKey(raw: Uint8Array): Promise<CryptoKey>` (AES-GCM, non-extractable, encrypt+decrypt not needed: decrypt only); `openRotation(deviceKey: CryptoKey, mirrorId, deviceId, epoch: number, sealed: Uint8Array): Promise<{epoch: number, dataKey: Uint8Array}>` (throws `CryptoFailure` on any failure, including an inner `epoch` different from the argument); `openWrap` also returns `deviceKey: Uint8Array | null` (`null` when the wrap has none).
- Produces (Swift): `MirrorCrypto.sealRotation(deviceKey: Data, mirrorID: String, deviceID: String, epoch: Int, dataKey: Data, iv: Data?) throws -> Data`; `MirrorCrypto.sealWrap(...)` takes an optional `deviceKey: Data?` added to the JSON.
- Vector JSON gains `rotation: {deviceKeyHex, mirrorId, deviceId, epoch, ivHex, newDataKeyHex, expectedSealed}`.

- [ ] **Step 1: Write failing tests (RED)** on both sides: the vector's blob is reproduced byte for byte by `sealRotation` (Swift) and opened by `openRotation` (JS) to the same `dataKey`; wrong `mirrorId`, wrong `deviceId`, wrong `epoch` argument, a flipped byte, a 27-byte input, and an inner epoch mismatch all fail; a wrap with `deviceKey` round-trips and one without opens with `deviceKey === null`.
- [ ] **Step 2: Extend** `make-vectors.mjs` and `verify-vectors.py` (independent recomputation), regenerate the fixture, implement both sides, add the Protocol text. **Step 3: Run** `npm --prefix web test`, `python3 web/scripts/verify-vectors.py`, `bash scripts/check-conventions.sh`; commit `feat(mirror): device keys and rotation blobs (protocol, vectors, crypto)`.

### Task 3: Phone rotates on remove

**Files:**
- Modify: `Palabra/Features/Mirroring/Storage/MirrorSecrets.swift`, `Net/MirrorClient.swift`, `Pairing/MirrorPairingSession.swift`, `Sync/MirrorService.swift`, `Palabra/Features/Settings/MirroringSettingsView.swift`, `Palabra/Resources/ar.lproj/Localizable.strings`, `PalabraTests/App/LocalizationTests.swift`, `PalabraTests/Mirroring/MirrorStorageTests.swift`, `MirrorClientTests.swift`, `MirrorPairingSessionTests.swift`, `MirrorServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 endpoints; `MirrorCrypto.sealRotation/sealWrap` (Task 2).
- Produces: `MirrorComputer.deviceKey: String?`; `MirrorSecrets.epoch: Int`, `MirrorSecrets.pending: MirrorSecrets.Pending?` (`struct Pending: Codable, Equatable { var dataKey: String; var epoch: Int }`); `MirrorClient.rotate(mirrorID:bearer:epoch:remove:blobs:) async throws -> Int` (new epoch), `MirrorClient.state(mirrorID:bearer:) async throws -> MirrorState` (`seq: Int`, `epoch: Int`; the old `state` returning only `Int` becomes this); `MirrorService.remove(computerID:) async` now rotates as described in Global Constraints; `MirrorService.promotePendingIfNeeded() async`; `MirrorService.computersNeedingRepair: [MirrorComputer]` (those with `deviceKey == nil`).

- [ ] **Step 1: Write failing tests** (`MockURLProtocol`, inspect real bodies): secrets decode without `epoch/pending/deviceKey` (tolerant) and round-trip with them; the pairing session's wrap now includes a `deviceKey` (open the sealed wrap with the vector keys and assert it is 32 bytes) and the computer is stored with the same value; `remove` with two computers (one with `deviceKey`, one without): the `POST /rotate` body has `epoch == 1`, `remove == id`, `blobs` with exactly the one capable computer, whose blob opens with that computer's `deviceKey` to the **new** key (not the old); the other computer is reported removed; the Keychain holds the new key only after the 200 and held it as `pending` during the request (assert via a handler that reads the store mid-request); after success the index is empty and a sync sends the items sealed under the new key (open one with the new key; the old key fails); `remove` of the last computer rotates with `blobs == {}`; a `409 stale_epoch` leaves secrets unchanged (pending cleared), lastError set and no loop (exactly one retry of `state`, no second `rotate`); a network failure on `rotate` keeps the old key live and the computer listed; promotion: pending present and `state.epoch == pending.epoch` promotes on the next `sync`/start, pending present and epoch still old is discarded; a `404` on remove of an already removed device is still treated as removed but does **not** rotate.
- [ ] **Step 2: Implement** (new key from `MirrorCrypto.randomBytes(32)`; save `pending` first, call `rotate`, then promote and `index.reset()` and force-sync). **Settings screen:** after a removal that dropped computers without a key, show a note naming them; strings: "Paired before key rotation existed; pair it again." and "Removing this computer replaces the encryption key. The other computers keep working." (confirmation text), both with Arabic and `LocalizationTests` entries. **Step 3: `bash scripts/check-conventions.sh`; commit** `feat(mirror): rotate the data key when a computer is removed`.

### Task 4: The page follows a rotation

**Files:**
- Modify: `web/src/api.js`, `web/src/localdb.js`, `web/src/sync.js`, `web/src/pairing.js`, `web/src/main.js`, `web/src/strings.js` (no new visible string expected; add one only if the UI needs it), `web/test/sync.test.js`, `web/test/pairing.test.js`, `web/test/localdb.test.js`

**Interfaces:**
- Produces: `api.state(mirrorId, bearer): Promise<{seq, epoch}>` and `api.rotation(mirrorId, bearer): Promise<{epoch, blob}>` (404 -> `ApiError`); credentials gain `epoch: number` (default 0) and `deviceKey: CryptoKey | null`; `pullOnce` first calls `state()`; if `state.epoch > creds.epoch` it runs the rekey described in Global Constraints before pulling; a failure to rekey throws `AuthRevoked`; the pairing `accept()` result includes `deviceKey` and `main.js` stores it with `epoch: 0`.

- [ ] **Step 1: Write failing tests** (existing `setup/sealed/fakeApi` helpers; extend `fakeApi` with `state` and `rotation`): pairing stores a non-extractable `deviceKey` from the wrap (and `null` when absent); `pullOnce` with a higher epoch and a good blob replaces keys and epoch, clears old rows and `lastSeq`, then pulls the new-epoch items and applies them (`check.state === "verified"` with a manifest sealed under the new key); a higher epoch with no blob (404) -> `AuthRevoked` and the local copy is cleared by the caller as today; a blob sealed for another device id or another epoch -> `AuthRevoked`; creds without `deviceKey` and a higher epoch -> `AuthRevoked`; an old-epoch item arriving after rekey is counted as rejected, never stored; `state.seq` lower than saved `lastSeq` in the **same** epoch still throws `RollbackDetected` (plan 3a), but right after a rekey (`lastSeq` reset) it does not; the 401 of a removed device still maps to `AuthRevoked`.
- [ ] **Step 2: Implement. Step 3: `npm --prefix web test`; build; commit** `feat(web): follow a key rotation or show "removed"`.

### Task 5: Phase check, CI, report

**Files:**
- Modify: `web/scripts/e2e-local.mjs` (from plan 3a), `docs/features/mirroring.md` (Trust model: what revoking now does and does not do; Known gaps), `AGENTS.md` (frozen names: `deviceKey`, epoch, rotation AAD prefix)

- [ ] **Step 1: Extend `e2e-local.mjs`:** two JS-phone-paired browsers (two contexts); revoke browser A through the rotation endpoint with a blob for B; page A shows "This computer was removed"; page B reloads, rekeys, shows the re-pushed words, and its IndexedDB holds no rows sealed under the old key (open every stored row's source item with the new key). Run it locally.
- [ ] **Step 2: Whole-repo checks** (web tests, worker tests, vector verify + `git diff --exit-code` on the fixture after rerun, conventions). Push once; read Build (ipa + tests) and Mirror workflows; fix and push again if needed.
- [ ] **Step 3: Docs** as listed. **Step 4: Report:** what revoking does now, the limits (a removed computer keeps what it already downloaded; computers paired before this change need re-pairing to survive a rotation), what CI cannot prove.
