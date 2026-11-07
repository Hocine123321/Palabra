# Mirroring, plan 2: pairing and the first records

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pair a computer to the phone with a QR code and a match code confirmed on both sides, push the words library to the Worker as sealed items, and show those words in the web page from its own local copy.

**Architecture:** One written protocol (v1) with fixed test vectors that both a JavaScript and a Swift implementation must reproduce. The phone (`Features/Mirroring`) generates every secret, talks to the Worker from plan 1 over REST, and seals each word into an opaque item. The web page (`web/src`) pairs, pulls items, opens them with a non-extractable key, stores them in IndexedDB and renders from there.

**Tech Stack:** Swift/SwiftUI/CryptoKit/AVFoundation (iOS 17), XCTest with `MockURLProtocol`; web: plain ES modules, WebCrypto, IndexedDB, `esbuild` and `qrcode-generator` (bundled at build time, no CDN), `fake-indexeddb` for tests, Node `node --test`; Python `cryptography` for one independent check of the vectors.

**Spec:** `docs/superpowers/specs/2026-11-07-mirroring-design.md` (Keys and sealing, Pairing, Syncing data, The web app, Phone side, Phase 2). **Builds on:** `docs/superpowers/plans/2026-11-07-mirroring-1-worker.md` (the Worker and its REST API; its error codes and limits apply here).

## Global Constraints

- **Protocol v1** (all values below are normative; `docs/features/mirroring.md` gets a "Protocol v1" section in Task 1):
  - Base64url means unpadded (`A-Z a-z 0-9 - _`). Ids (`pairId`, `mirrorId`, `deviceId`) are 16 random bytes = 22 characters; tokens and the data key are 32 random bytes.
  - `dataKey` (32 bytes) never leaves phone and paired browsers. Two keys are derived with HKDF-SHA-256, empty salt, length 32: `kAes` with info `"palabra-mirror-aes-v1"` and `kId` with info `"palabra-mirror-id-key-v1"`.
  - **Item id** = base64url of the first 16 bytes of HMAC-SHA-256(`kId`, UTF-8 of `kind + "|" + recordId`) (22 characters).
  - **Sealed item** = `iv(12 random) | AES-256-GCM(kAes) ciphertext | tag(16)`, associated data = UTF-8 of `"palabra-mirror-item-v1|" + itemId`; sent as base64url.
  - **Item plaintext** = UTF-8 JSON `{"v":1,"k":<kind>,"r":<recordId>,"h":<content hash hex>,"g":<generation>,"d":<payload object>}`. `g` increases with every push that sends anything; the browser keeps the row with the higher `g`; only the phone computes `h`.
  - **Pair keys:** ECDH P-256; public keys are raw uncompressed points (65 bytes, base64url = 87 characters); shared secret = the 32-byte X coordinate; `kPair` = HKDF-SHA-256(ikm = shared, salt = the 16-byte nonce, info = `"palabra-mirror-pair-v1"`, length 32), used as an AES-256-GCM key.
  - **Match code** = the first 4 bytes of SHA-256(`browserPub | phonePub | nonce`) as a big-endian unsigned integer, modulo 10000, zero-padded to 4 digits.
  - **Wrap** (phone -> browser) = `iv(12) | AES-256-GCM(kPair) | tag` over UTF-8 JSON `{"v":1,"mirrorId","deviceId","deviceToken","dataKey"}` (`dataKey` base64url), associated data = UTF-8 of `"palabra-mirror-wrap-v1|" + pairId`.
  - **QR link:** `https://<worker host>/#p=<pairId>&k=<browserPub>&n=<nonce>` (nonce 16 bytes). `http` is accepted only for `localhost` and `127.0.0.1`.
  - **Bearer:** `Authorization: Bearer <deviceId>.<token>`; the server is only ever sent `sha256Hex(token)`.
- **No secret in any request body, URL, log or error text.** Tokens, the data key and private keys appear only in the Keychain / IndexedDB and inside sealed wraps.
- **The match code needs a human yes on both sides** (phone Confirm, browser "Codes match") before keys are released or accepted.
- Repo rules: `Features/Mirroring` imports no `Word`, `Deck`, `Card`, `ReviewNeed` (data arrives as `MirrorRecord` from `App/AppEnvironment+Mirror.swift`); new persisted names are the Keychain account `mirror-secrets`, the `UserDefaults` key `mirrorSettings` (tolerant decoder) and the file `Application Support/Mirror/index.json`; every new UI string has an Arabic key and a `LocalizationTests` entry; UI strings in the web page have Arabic too; new network code is tested by inspecting the actual request (`MockURLProtocol`), not just that a request happened; no direct `withAnimation`/`.animation(`; after finishing, say plainly that Swift was compiled by eye only and needs a real CI run, and that the camera scan, Safari/Chrome and the real Worker were not exercised by CI.
- Not in this plan: service worker and offline *loading* of the page (phase 3; this plan renders from the local copy once loaded), other collections than words, the manifest and rollback check, the mailbox, the live channel, key rotation.

## Review Focus

- A tampered sealed item, a wrong item id, or a wrong-length key never produces partial or garbage data: opening fails and the item is counted as rejected.
- A scanned link that is hostile or odd (`http://` non-local, extra parameters, uppercase hex, a 64-byte key, a second scan of a used slot, a slot someone else joined first) fails with a clear message and sends nothing.
- A push that dies halfway (offline, 401, 429) leaves the index describing only what the server really has, so the next push resends the rest; deleting a word sends a tombstone.
- Words in Arabic or with markup (`<img onerror=...>`) and a word whose content is close to the 262,144-character item cap: they round-trip, render as text, or are skipped and reported, never crash the push or the page.
- A removed computer (token revoked) sees "This computer was removed" instead of an endless spinner, and a double tap on Confirm pairs once.

---

## File structure

```
docs/features/mirroring.md                          + "Protocol v1" section
PalabraTests/Mirroring/Fixtures/mirror-vectors.json  shared vectors (single source)
web/scripts/make-vectors.mjs  verify-vectors.py  build.mjs (extended)
web/src/b64url.js crypto.js api.js pairing.js qr.js localdb.js sync.js strings.js view.js main.js app.css
web/test/*.test.js
Palabra/Features/Mirroring/Crypto/MirrorCrypto.swift
Palabra/Features/Mirroring/Net/MirrorClient.swift
Palabra/Features/Mirroring/Storage/MirrorSecrets.swift  MirrorSettings.swift  MirrorIndex.swift
Palabra/Features/Mirroring/Pairing/PairingLink.swift  MirrorPairingSession.swift  QRScannerView.swift
Palabra/Features/Mirroring/Sync/MirrorRecord.swift  MirrorPusher.swift  MirrorService.swift
Palabra/App/AppEnvironment+Mirror.swift
Palabra/Features/Settings/MirroringSettingsView.swift   (+ a row in SettingsView.swift)
PalabraTests/Mirroring/*.swift
```

---

### Task 1: Protocol doc, shared vectors, JavaScript crypto

**Files:**
- Create: `web/src/b64url.js`, `web/src/crypto.js`, `web/scripts/make-vectors.mjs`, `web/scripts/verify-vectors.py`, `PalabraTests/Mirroring/Fixtures/mirror-vectors.json`, `web/test/crypto.test.js`
- Modify: `docs/features/mirroring.md` (add "Protocol v1": the Global Constraints list above, verbatim), `.github/workflows/mirror.yml` (add steps: `pip install cryptography`, `python3 web/scripts/verify-vectors.py`)

**Interfaces:**
- Produces (`b64url.js`): `encode(bytes: Uint8Array): string`, `decode(text: string): Uint8Array` (throws `Error("bad base64url")` on any character outside the alphabet, including `=`, `+`, `/`).
- Produces (`crypto.js`, WebCrypto only):
  - `importDataKey(raw: Uint8Array): Promise<{aes: CryptoKey, id: CryptoKey}>` (both non-extractable)
  - `deriveItemId(keys, kind: string, recordId: string): Promise<string>`
  - `sealItem(keys, itemId: string, plaintext: Uint8Array, iv?: Uint8Array): Promise<Uint8Array>`; `openItem(keys, itemId, sealed: Uint8Array): Promise<Uint8Array>` (rejects with `CryptoFailure` on any failure, including input shorter than 28 bytes)
  - `generatePairKeys(): Promise<{privateKey: CryptoKey, publicRaw: Uint8Array}>`
  - `deriveKPair(privateKey: CryptoKey, otherPublicRaw: Uint8Array, nonce: Uint8Array): Promise<CryptoKey>` (rejects if the public key is not 65 bytes starting `0x04`)
  - `matchCode(browserPub: Uint8Array, phonePub: Uint8Array, nonce: Uint8Array): Promise<string>`
  - `openWrap(kPair: CryptoKey, pairId: string, sealed: Uint8Array): Promise<{mirrorId, deviceId, deviceToken, dataKey: Uint8Array}>`
  - `class CryptoFailure extends Error`

- [ ] **Step 1: Write `make-vectors.mjs`** (Node `crypto`, fixed inputs, deterministic): `dataKey` = bytes 0x00..0x1f; kind `"word"`, recordId `"6F9619FF-8B86-D011-B42D-00C04FC964FF"`; item iv = 12 bytes of 0x10; plaintext = the JSON envelope `{"v":1,"k":"word","r":"6F9619FF-8B86-D011-B42D-00C04FC964FF","h":"abc123","g":7,"d":{"spanish":"mañana","translation":"tomorrow","tags":["tiempo"]}}`; browser private key `d` = 32 bytes of 0x11, phone private key `d` = 32 bytes of 0x22 (derive their public points with `crypto.createECDH("prime256v1")`); nonce = 16 bytes of 0x33; `pairId` = base64url of 16 bytes of 0x44; wrap plaintext `{"v":1,"mirrorId":"MIRRORID","deviceId":"DEVICEID","deviceToken":"TOKEN","dataKey":"<base64url of the 32 bytes above>"}` with iv = 12 bytes of 0x55. It writes `PalabraTests/Mirroring/Fixtures/mirror-vectors.json` with hex for raw bytes and base64url for sealed values and ids: `{dataKeyHex, id: {kind, recordId, expected}, item: {plaintextUtf8, ivHex, expectedSealed}, pair: {browserPrivHex, phonePrivHex, browserPubHex, phonePubHex, nonceHex, pairId, kPairHex, matchCode}, wrap: {plaintextUtf8, ivHex, expectedSealed}}`. The kAes/kId/kPair derivations in this script are written independently of `src/crypto.js`.
- [ ] **Step 2: Write `verify-vectors.py`** recomputing every expected value with Python `cryptography` (HKDF, HMAC, AES-GCM, ECDH) and exiting non-zero on any mismatch. Run `node web/scripts/make-vectors.mjs && python3 web/scripts/verify-vectors.py` -> prints OK (this is the one independent cross-check).
- [ ] **Step 3: Write failing tests** in `web/test/crypto.test.js` reading the JSON: `deriveItemId` equals `id.expected`; `sealItem(..., iv)` equals `item.expectedSealed` byte for byte and `openItem` returns the plaintext; `openItem` with one flipped bit in the ciphertext, in the tag, in the iv, with a different `itemId`, and with a 10-byte input each rejects with `CryptoFailure`; the browser private key (import via a JWK built from the vector's public point and `d`) with the phone's public key gives `kPair` that can open `wrap.expectedSealed` into the expected object (`dataKey` bytes equal to the vector's); `matchCode` equals `pair.matchCode` and changes when any one of the three inputs changes by a byte; `deriveKPair` rejects a 64-byte key and a key starting `0x02`; `generatePairKeys` returns a 65-byte `publicRaw` starting `0x04`; `b64url.decode` rejects `"ab="`, `"a+b"`, `"a/b"` and round-trips random byte arrays of lengths 0..40.
- [ ] **Step 4: Run** `node --test web/test/crypto.test.js` -> FAIL (modules missing).
- [ ] **Step 5: Implement** `b64url.js` and `crypto.js`. `importDataKey` imports the raw bytes as HKDF key material and derives the two keys with `deriveKey` (AES-GCM 256 `encrypt/decrypt`, and HMAC SHA-256 `sign`), both `extractable: false`.
- [ ] **Step 6: Run** the web tests -> PASS; commit `feat(mirror): protocol v1 vectors and JavaScript crypto`.

---

### Task 2: Swift crypto reproduces the vectors

**Files:**
- Create: `Palabra/Features/Mirroring/Crypto/MirrorCrypto.swift`, `PalabraTests/Mirroring/MirrorCryptoTests.swift`

**Interfaces:**
- Consumes: `mirror-vectors.json` (loaded from the test bundle with the same `bundle.url(forResource:withExtension:)` pattern as `GoldenFixtures`).
- Produces:
  - `enum Base64URL { static func encode(_ data: Data) -> String; static func decode(_ text: String) -> Data? }` (nil on any invalid character, padding included)
  - `struct MirrorKeys { init(dataKey: Data); static func randomDataKey() -> Data }` (derives `kAes`, `kId` as `SymmetricKey`)
  - `enum MirrorCrypto { enum Failure: Error { case malformed, authentication, badKey }; static func itemID(keys: MirrorKeys, kind: String, recordID: String) -> String; static func sealItem(keys: MirrorKeys, itemID: String, plaintext: Data, iv: Data? = nil) throws -> Data; static func openItem(keys: MirrorKeys, itemID: String, sealed: Data) throws -> Data; static func agree(privateKey: P256.KeyAgreement.PrivateKey, otherPublic: Data, nonce: Data) throws -> SymmetricKey; static func matchCode(browserPublic: Data, phonePublic: Data, nonce: Data) -> String; static func sealWrap(key: SymmetricKey, pairID: String, plaintext: Data, iv: Data? = nil) throws -> Data; static func openWrap(key: SymmetricKey, pairID: String, sealed: Data) throws -> Data; static func randomBytes(_ count: Int) -> Data }`

- [ ] **Step 1: Write failing tests** in `MirrorCryptoTests` (each assertion uses the vector file): `itemID` equals `id.expected`; `sealItem` with the vector iv equals `item.expectedSealed` (compare as base64url strings) and `openItem` returns the plaintext bytes; flipped ciphertext bit, flipped tag bit, wrong item id and a 10-byte input each throw (`.authentication` / `.malformed`); `agree` with the phone private key (from `phonePrivHex`) and the browser public key gives `kPair` whose raw bytes equal `pair.kPairHex` (`withUnsafeBytes`), and the same from the browser side gives the same key; `agree` throws `.badKey` for a 64-byte key and for a point not on the curve; `matchCode` equals `pair.matchCode`; `sealWrap` with the vector iv equals `wrap.expectedSealed` and `openWrap` round-trips; `Base64URL.decode("ab=")`, `"a+b"` are nil and random data round-trips; `randomBytes(32)` twice differ.
- [ ] **Step 2: Implement** `MirrorCrypto.swift` with CryptoKit: HKDF via `HKDF<SHA256>.deriveKey(inputKeyMaterial:salt:info:outputByteCount:)`, HMAC via `HMAC<SHA256>`, AES via `AES.GCM` (`SealedBox.combined` is already `iv | ciphertext | tag`), key agreement via `P256.KeyAgreement` with `sharedSecretFromKeyAgreement` then `hkdfDerivedSymmetricKey(using: SHA256.self, salt: nonce, sharedInfo: ..., outputByteCount: 32)`.
- [ ] **Step 3: Push and read CI** (`gh run view`; the tests job): `MirrorCryptoTests` pass. If a vector mismatches, the bug is in the Swift side unless `verify-vectors.py` also fails.
- [ ] **Step 4: Commit** `feat(mirror): Swift crypto matching the shared vectors`.

---

### Task 3: Web pairing client

**Files:**
- Create: `web/src/api.js`, `web/src/pairing.js`, `web/src/qr.js`, `web/test/pairing.test.js`
- Modify: `web/package.json` (dependencies `qrcode-generator`, devDependencies `esbuild`, `fake-indexeddb`; scripts); run `npm install` in `web/` and commit the lockfile; `.github/workflows/mirror.yml` (`npm ci` in `web` before its tests)

**Interfaces:**
- Consumes: `crypto.js`, `b64url.js`; the Worker REST API from plan 1.
- Produces:
  - `api.js`: `createApi(origin: string, fetchImpl = fetch): {pairStart(): Promise<{pairId, expiresAt}>, pairGet(pairId): Promise<{state, phonePub?, sealed?}>, pairCancel(pairId): Promise<void>, state(mirrorId, bearer): Promise<{seq}>, items(mirrorId, bearer, since: number, limit = 200): Promise<{items, seq, more}>}`; `class ApiError extends Error {status: number, code: string}`; `class OfflineError extends Error` (thrown when `fetch` itself rejects).
  - `pairing.js`: `createPairing({api, origin, now = Date.now}): {start(): Promise<{link: string, pairId: string, expiresAt: number}>, poll(): Promise<{state: "waiting" | "joined" | "replied" | "cancelled" | "expired", code?: string}>, accept(): Promise<{mirrorId, deviceId, deviceToken, dataKey: Uint8Array}>, cancel(): Promise<void>}`. `poll` returns `code` once the phone has joined (computed from the slot's `phonePub`); `accept` is only allowed after `poll` returned `replied` and throws otherwise; `expired` is reported locally once `now() > expiresAt`.
  - `qr.js`: `qrTree(text: string): VNode` where `VNode = {tag: string, attrs: object, children: (VNode | string)[]}` for an `<svg>` with one `<path>` (no inline styles).

- [ ] **Step 1: Write failing tests** `pairing.test.js` with an end-to-end harness: `handleApi` and `makeMemoryBackend` imported from `../../worker/src/router.js` and `../../worker/test/support/memory-backend.js`, wrapped as a `fetchImpl`, plus a JS "fake phone" in the test that uses `crypto.js` primitives to join and reply like plan 2's phone does (`generatePairKeys`, `deriveKPair`, a `sealWrap` written in the test with `crypto.subtle` per Protocol v1). Cases: `start` returns a link of the form `https://x.test/#p=<22>&k=<87>&n=<22>` that parses back to the same `pairId`, a 65-byte key and a 16-byte nonce; polling before the phone joins gives `waiting`; after the join `poll` gives `joined` with the same 4-digit code the phone computed; after the reply `poll` gives `replied`, and `accept` returns the exact `mirrorId`, `deviceId`, `deviceToken` and 32-byte `dataKey` the fake phone sealed; `accept` before `replied` throws; a second `accept` throws (the slot was read once); an attacker who joined first (a second join gets 409) leaves the real phone's join failing and `poll` showing the attacker's code (the test asserts the code differs from the real phone's); a reply sealed under a different key makes `accept` reject with `CryptoFailure` and return nothing; `cancel` then `poll` reports `cancelled`; with a stub clock past `expiresAt`, `poll` reports `expired` without a request; `ApiError` carries `status` and `code` from a 429 and `OfflineError` is thrown when `fetchImpl` rejects; `qrTree("https://x.test/#p=1")` has tag `svg`, no `style` attribute anywhere, and a `path` whose `d` is non-empty.
- [ ] **Step 2: Run** `node --test web/test/pairing.test.js` -> FAIL.
- [ ] **Step 3: Implement** the three modules. `start` keeps the private key in memory only. `poll` calls `pairGet` and maps server states; the link's origin comes from the `origin` argument.
- [ ] **Step 4: Run** all web tests -> PASS; commit `feat(mirror): web pairing client`.

---

### Task 4: Swift secrets, settings and REST client

**Files:**
- Create: `Palabra/Features/Mirroring/Storage/MirrorSecrets.swift`, `Palabra/Features/Mirroring/Storage/MirrorSettings.swift`, `Palabra/Features/Mirroring/Net/MirrorClient.swift`, `PalabraTests/Mirroring/MirrorClientTests.swift`, `PalabraTests/Mirroring/MirrorStorageTests.swift`

**Interfaces:**
- Consumes: `KeychainStore(account:)`, `MockURLProtocol`, `Box`, `Base64URL`.
- Produces:
  - `struct MirrorComputer: Codable, Equatable, Identifiable { let id: String /* deviceID */; var name: String; let pairedAt: Date }`
  - `struct MirrorSecrets: Codable, Equatable { var origin: String; var mirrorID: String; var ownerDeviceID: String; var ownerToken: String; var dataKey: String /* base64url */; var computers: [MirrorComputer]; var bearer: String { ownerDeviceID + "." + ownerToken } }`
  - `struct MirrorSecretsStore { init(keychain: KeychainStore = KeychainStore(account: "mirror-secrets")); func load() -> MirrorSecrets?; func save(_ secrets: MirrorSecrets) -> Bool; func clear() }` (JSON in the keychain string; a corrupt value loads as nil).
  - `struct MirrorSettings: Codable, Equatable { var enabled: Bool = false; var lastSyncAt: Date? = nil }` with a tolerant `init(from:)` (every field optional) and `final class MirrorSettingsStore { init(defaults: UserDefaults = .standard); var value: MirrorSettings { get set } }` under the key `mirrorSettings`.
  - `enum MirrorClientError: Error, Equatable { case http(status: Int, code: String), offline, badResponse }`
  - `struct MirrorClient { init(origin: URL, session: URLSession = .shared); func createMirror(deviceID: String, ownerTokenHash: String) async throws -> String; func pairJoin(pairID: String, phonePublic: Data) async throws; func pairReply(pairID: String, sealed: Data) async throws; func pairCancel(pairID: String) async throws; func addDevice(mirrorID: String, bearer: String, deviceID: String, tokenHash: String) async throws; func removeDevice(mirrorID: String, bearer: String, deviceID: String) async throws; func putItems(mirrorID: String, bearer: String, items: [PutItem]) async throws -> Int; func state(mirrorID: String, bearer: String) async throws -> Int }` with `struct PutItem: Equatable { let id: String; let sealed: String; let deleted: Bool }`. Paths and bodies are exactly those in plan 1's route table; `URLError.notConnectedToInternet`/`.timedOut`/`.networkConnectionLost` map to `.offline`; a non-2xx response maps to `.http(status, code)` using the body's `error` field (or `"unknown"`).

- [ ] **Step 1: Write failing tests.** `MirrorClientTests` (install `MockURLProtocol.session()`, capture requests in a `Box`): `createMirror` sends `POST /api/mirrors` with a JSON body whose keys are exactly `deviceId` and `ownerTokenHash`, content type `application/json`, no `Authorization` header, and returns the `mirrorId` from the 201 body; `pairJoin` body is exactly `{"phonePub": <87-char base64url of the 65 bytes>}` to `/api/pair/<id>/join`; `pairReply` body `{"sealed": <base64url>}`; `addDevice` carries `Authorization: Bearer <bearer>` and body keys `deviceId`, `tokenHash`; `removeDevice` is `DELETE /api/m/<mirror>/devices/<device>`; `putItems` body is `{"items":[{"id","sealed"} or with `"deleted":true`]}` with `PUT`, and returns `seq`; 409 `{"error":"slot_taken"}` throws `.http(status: 409, code: "slot_taken")`; 429 and 401 likewise; a transport `URLError(.notConnectedToInternet)` throws `.offline`; a 200 with a non-JSON body throws `.badResponse`; the origin's port and path prefix are respected (`https://x.test:8443`). `MirrorStorageTests`: secrets round-trip through a Keychain account named `mirror-secrets-test-<UUID>` (deleted in `tearDown`); a stored garbage string loads as nil; `MirrorSettings` decodes `{}` and `{"enabled":true}` and an unknown extra field without failing.
- [ ] **Step 2: Implement** the three files. The client builds URLs with `URLComponents` on the origin; it never logs bodies.
- [ ] **Step 3: Push, read CI**, tests pass; commit `feat(mirror): Mirror client, secrets store and settings`.

---

### Task 5: Pairing on the phone (link parsing and session)

**Files:**
- Create: `Palabra/Features/Mirroring/Pairing/PairingLink.swift`, `Palabra/Features/Mirroring/Pairing/MirrorPairingSession.swift`, `PalabraTests/Mirroring/PairingLinkTests.swift`, `PalabraTests/Mirroring/MirrorPairingSessionTests.swift`

**Interfaces:**
- Consumes: `MirrorCrypto`, `MirrorClient`, `MirrorSecretsStore`, `Base64URL`.
- Produces:
  - `struct PairingLink: Equatable { let origin: URL; let pairID: String; let browserPublic: Data; let nonce: Data; static func parse(_ text: String) -> Result<PairingLink, PairingLinkError> }`; `enum PairingLinkError: Error { notALink, insecureOrigin, missingField(String), badField(String) }`. Rules: scheme `https` (or `http` for `localhost`/`127.0.0.1`), no user info, parameters `p` (22 base64url characters), `k` (decodes to 65 bytes, first byte `0x04`), `n` (decodes to 16 bytes), each exactly once, extra parameters ignored, surrounding whitespace trimmed; `origin` is scheme + host + port only.
  - `@MainActor @Observable final class MirrorPairingSession { enum Phase: Equatable { case idle, joining, awaitingConfirmation(code: String), finishing, done, failed(Failure), cancelled }; enum Failure: Equatable { case slotTaken, expired, offline, alreadyPairedElsewhere, tooManyComputers, rateLimited, other }; private(set) var phase: Phase; init(link: PairingLink, client: MirrorClient, secrets: MirrorSecretsStore, makeKey: @escaping () -> P256.KeyAgreement.PrivateKey = { .init() }, randomBytes: @escaping (Int) -> Data = MirrorCrypto.randomBytes, now: @escaping () -> Date = Date.init); func start() async; func confirm() async; func cancel() async }`.
  - Behaviour: `start` fails with `.alreadyPairedElsewhere` (sending nothing) when stored secrets have a different origin; otherwise generates the phone key, `pairJoin`, derives `kPair` and the code, and moves to `awaitingConfirmation`. `confirm` (ignored unless awaiting, so a double tap pairs once): with no stored secrets it generates `dataKey` (32 bytes), `ownerDeviceID` (16 bytes base64url), `ownerToken` (32 bytes base64url), calls `createMirror` with `sha256Hex(ownerToken)` and saves the secrets; then generates the browser `deviceID` and `deviceToken`, `addDevice` with the hash, seals the wrap JSON with `sealWrap(kPair, pairID)`, `pairReply`; then appends `MirrorComputer(name: "Computer \(n)")` to the saved secrets. If anything fails after `addDevice`, it best-effort calls `removeDevice` for that device. `cancel` calls `pairCancel` (errors ignored) and moves to `cancelled`. HTTP 409 `slot_taken` -> `.slotTaken`, 404/410 -> `.expired`, 409 `too_many_devices` -> `.tooManyComputers`, 429 -> `.rateLimited`, `.offline` -> `.offline`.

- [ ] **Step 1: Write failing tests.** `PairingLinkTests`: the valid link from the vectors parses to the expected fields; `http://example.com/#...` -> `.insecureOrigin`; `http://localhost:8787/#...` accepted; missing `p`, `k` or `n` -> `.missingField("p")` etc.; `k` of 64 bytes, `k` starting `0x02`, `n` of 15 bytes, `p` of 21 characters, uppercase-hex garbage, a repeated `p` -> `.badField(...)`; `https://u:pw@x.test/#...` -> `.insecureOrigin`; an extra `&z=1` is ignored; leading/trailing newline is trimmed; random text -> `.notALink`. `MirrorPairingSessionTests` with `MockURLProtocol`, the vector's browser key and nonce, and fixed phone key/random bytes: the join request body carries the phone's public key as 87 characters; the session reaches `awaitingConfirmation` with the code equal to the vector's `matchCode`; before `confirm` no request has been sent to `/api/mirrors`, `/devices` or `/reply`; after `confirm`: the `/api/mirrors` body `ownerTokenHash` equals the SHA-256 hex of the `ownerToken` saved in the secrets store, the `/devices` request carries the owner bearer and the hash of the device token, the `/reply` body `sealed` opens with the browser-side `kPair` (computed from the vector's browser private key and the phone's public key from the join request) into JSON whose `deviceToken` hashes to the `tokenHash` that was sent and whose `dataKey` equals the stored one; **no request body or URL contains** the owner token, the device token or the data key in clear; a second `confirm()` call right after the first sends no further requests; with existing secrets for the same origin no `/api/mirrors` call is made and a computer is appended; with secrets for another origin `start` ends in `.failed(.alreadyPairedElsewhere)` with zero requests; join 409 `slot_taken` -> `.failed(.slotTaken)`; `/devices` failing after `createMirror` keeps the saved secrets and no reply is sent; reply failing triggers a `removeDevice` request; `cancel` sends `/cancel` and ends `.cancelled`.
- [ ] **Step 2: Implement** both files.
- [ ] **Step 3: Push, read CI**; commit `feat(mirror): pairing link parsing and phone pairing session`.

---

### Task 6: Records, index, pusher, words data source

**Files:**
- Create: `Palabra/Features/Mirroring/Sync/MirrorRecord.swift`, `Palabra/Features/Mirroring/Storage/MirrorIndex.swift`, `Palabra/Features/Mirroring/Sync/MirrorPusher.swift`, `Palabra/App/AppEnvironment+Mirror.swift`, `PalabraTests/Mirroring/MirrorIndexTests.swift`, `PalabraTests/Mirroring/MirrorPusherTests.swift`, `PalabraTests/Mirroring/MirrorWordRecordsTests.swift`

**Interfaces:**
- Consumes: `MirrorCrypto`, `MirrorKeys`, `MirrorClient`, `MirrorSecrets`, `JSONValue`.
- Produces:
  - `struct MirrorRecord: Equatable, Sendable { let kind: String; let recordID: String; let payload: JSONValue; var contentHash: String { get } }` (`contentHash` = SHA-256 hex of the payload's JSON with sorted keys, so the same content gives the same hash regardless of key order).
  - `final class MirrorIndex { init(fileURL: URL); static func standard() -> MirrorIndex /* Application Support/Mirror/index.json */; var generation: Int; func hash(of itemID: String) -> String?; func itemIDs(ofKind kind: String) -> [String]; func record(itemID: String, kind: String, hash: String); func remove(itemID: String); func save() throws; func reset() }` (file is JSON `{generation, items: {itemID: {kind, hash}}}`; a corrupt or missing file loads as empty).
  - `struct MirrorPushResult: Equatable { let sent: Int; let deleted: Int; let skipped: [String] /* recordIDs too large */; let seq: Int? }`
  - `struct MirrorPusher { init(client: MirrorClient, secrets: MirrorSecrets, index: MirrorIndex); func push(_ records: [MirrorRecord], kinds: Set<String>) async throws -> MirrorPushResult }`. Algorithm: compute each record's item id and hash; changed = index hash differs; tombstones = indexed ids of the given `kinds` absent from `records`; nothing changed -> no request and `generation` unchanged; otherwise `generation += 1`, seal changed records (plaintext envelope per Protocol v1 with this generation), skip any whose base64url sealed length exceeds 262,144 (reported in `skipped`, left out of the index), send in batches of at most 200 items and 900,000 sealed characters, and after each successful batch record its items in the index (removing tombstoned ids) and `save()`; a failed batch throws and leaves later batches' items unindexed.
  - `AppEnvironment.mirrorWordRecords() -> [MirrorRecord]` (kind `"word"`, recordID = the word's UUID string, payload keys `id, key, spanish, translation, partOfSpeech, category, tags, createdAt, updatedAt` (ISO 8601 strings) and `content` (the word's `WordContent` as JSON); never `pronunciationAudio`, `chatData` or `rawJSON`).

- [ ] **Step 1: Write failing tests.** `MirrorIndexTests`: records and removes persist across a new instance on the same file; a corrupt file loads empty; `reset` deletes the file. `MirrorPusherTests` (`MockURLProtocol`, a temp-directory index, secrets with the vector `dataKey`): three new records send one `PUT /api/m/<mirror>/items` with the owner bearer and three items whose `sealed` values open (via `MirrorCrypto.openItem` with the item id and the vector keys) into envelopes with `v == 1`, the right `k`, `r`, `g == 1`, `d` equal to the payload and `h` equal to `contentHash`; pushing the same records again sends no request; changing one payload sends exactly that item with `g == 2`; removing a record from the list sends a tombstone item (`deleted: true`, `sealed` empty) and drops it from the index; another `kind` in the index is untouched when it is not in `kinds`; 450 records are sent as 3 requests (200, 200, 50); a payload that seals to more than 262,144 characters is in `skipped` and not sent while its neighbours are; a 429 on the second of three batches throws after the first batch's items were indexed and a retry sends only the remaining items; a 401 throws `.http(status: 401, ...)` and indexes nothing; `contentHash` is identical for two payloads built with different key insertion order and differs when a value changes; Arabic text and `<img src=x onerror=alert(1)>` in a word survive the seal/open round trip unchanged. `MirrorWordRecordsTests` (in-memory `AppEnvironment` as in the existing tests, two saved words with different categories and tags): two records, kind `"word"`, `recordID == word.id.uuidString`, payload has `spanish`, `translation`, `category`, `tags`, `content` (with the examples count of the saved content) and has none of `pronunciationAudio`, `chatData`, `rawJSON`; an empty library gives `[]`.
- [ ] **Step 2: Implement** the files; `mirrorWordRecords()` lives in the App layer extension like `examWords()`.
- [ ] **Step 3: Push, read CI**; commit `feat(mirror): records, push index and words pusher`.

---

### Task 7: The web page (pull, local copy, words list)

**Files:**
- Create: `web/src/localdb.js`, `web/src/sync.js`, `web/src/strings.js`, `web/src/view.js`, `web/src/main.js`, `web/src/app.css`, `web/test/localdb.test.js`, `web/test/sync.test.js`, `web/test/view.test.js`, `web/test/tokens.test.js`
- Modify: `web/public/index.html` (link `app.css`, load `app.js` as a module script, `<div id="app">`), `web/scripts/build.mjs` (bundle `src/main.js` to `dist/app.js` with esbuild, format `iife`, minified, copy `src/app.css` to `dist/app.css`, then copy `public/`)

**Interfaces:**
- Consumes: `api.js`, `pairing.js`, `crypto.js`, `qr.js`.
- Produces:
  - `localdb.js`: `openLocalDb(idb = indexedDB): Promise<LocalDb>`; `LocalDb = {getCredentials(): Promise<Creds | null>, setCredentials(c: Creds): Promise<void>, clearAll(): Promise<void>, getLastSeq(): Promise<number>, applyPage(rows: ItemRow[], deletes: string[], lastSeq: number): Promise<void> /* one transaction */, getItem(id): Promise<ItemRow | undefined>, itemsByKind(kind: string): Promise<ItemRow[]>}` where `Creds = {mirrorId, deviceId, deviceToken, keys: {aes: CryptoKey, id: CryptoKey}}` and `ItemRow = {id, kind, recordId, g, d}`.
  - `sync.js`: `pullOnce({api, db}): Promise<{applied: number, deleted: number, rejected: number, seq: number}>` (pages through `items(since, 200)` until `more` is false; throws `AuthRevoked` on a 401/403 and `OfflineError` on network failure).
  - `strings.js`: `t(key: string, lang: string): string` for English keys with Arabic translations; `pickLang(navigatorLanguage: string): "en" | "ar"`; `dirFor(lang)`.
  - `view.js`: pure functions returning `VNode` trees (`h(tag, attrs, ...children)` helper): `pairScreen({link, status})`, `confirmScreen({code})`, `wordsScreen({words, syncedAt, lang})`, `removedScreen()`, plus `mount(root: Element, tree: VNode)` that builds DOM with `createElement`/`textContent` only.
  - `app.css`: custom properties `--surface --ink --ink-secondary --fill --accent --accent-deep --accent-soft` in `:root` and the dark values inside `@media (prefers-color-scheme: dark) { :root {...} }`, using the hex values from `Palabra/Core/DesignSystem/Theme.swift`.

- [ ] **Step 1: Write failing tests.**
  - `localdb.test.js` (with `fake-indexeddb`): credentials round-trip; `applyPage` writes rows, deletes ids and sets `lastSeq` atomically (an injected failure in the middle leaves nothing changed); `itemsByKind("word")` returns only words; `clearAll` empties everything. If `fake-indexeddb` cannot store `CryptoKey` objects, keep the keys behind a `KeyStore` interface with an in-memory implementation for tests and note it in a code comment; the real implementation still stores non-extractable keys.
  - `sync.test.js`: an in-memory fake `api.items` serving items sealed with `crypto.js` (envelope per Protocol v1): pulling two pages (limit 2 over 3 items) applies all and returns the last `seq`; a tombstone deletes the stored row; an item whose id does not equal `deriveItemId(kind, recordId)` is counted in `rejected` and not stored; a tampered sealed value is `rejected`; a row with higher `g` is not overwritten by an older item; a second pull from the saved `lastSeq` requests `since=<seq>`; a 401 from `api.items` throws `AuthRevoked` and stores nothing; `OfflineError` propagates and leaves the previous copy intact.
  - `view.test.js`: `wordsScreen` with a word `{spanish: "<img src=x onerror=alert(1)>", ...}` produces a tree in which that text only appears as a string child (walk the tree: no attribute named `innerHTML`, no `on*` attribute carrying data, no string child is interpreted as markup); a word list of 3 produces 3 rows with spanish, translation, category and tags; an empty list shows the empty-state text; Arabic UI: `pickLang("ar-DZ")` is `"ar"`, `dirFor("ar")` is `"rtl"`; every key used by `view.js` has an Arabic translation (collect keys through an exported `USED_KEYS` or by running each screen with a recording `t`).
  - `tokens.test.js`: parses `Theme.swift` for the `surface, ink, inkSecondary, fill, accentDeep, accentSoft` light/dark hex pairs and `accent` single hex and asserts each appears in `app.css` as `--<kebab-name>: #<hex>` in the matching block (case-insensitive).
- [ ] **Step 2: Run** `node --test web/test/` -> FAIL.
- [ ] **Step 3: Implement** the modules. `main.js` flow: open the local db; with credentials, render `wordsScreen` from the local copy first, then `pullOnce` and re-render (a failure shows a small status line, never blanks the list; `AuthRevoked` clears credentials and shows `removedScreen`); without credentials run the pairing screens (QR from `qrTree`, poll every 1,500 ms, `confirmScreen` with a "Codes match" button that calls `accept`, then `setCredentials` with keys from `importDataKey`, and a "Cancel" button that calls `cancel`; an expired slot offers "Start again"). Words are sorted newest first by `d.createdAt` and show `d.spanish`, `d.translation`, `d.category`, `d.tags`. No `innerHTML`, no inline styles or scripts, no network call except to the page's own origin.
- [ ] **Step 4: Run** `npm --prefix web run build` (produces `dist/app.js`, `dist/app.css`, `dist/index.html`) and all web tests -> PASS; check that `dist/index.html` contains no inline `<script>` body or `style=` attribute (add this as an assertion to `web/test/build.test.js`).
- [ ] **Step 5: Commit** `feat(mirror): web page pulls, decrypts and lists words from its local copy`.

---

### Task 8: Settings -> Mirroring, scanner, automatic push, strings, docs

**Files:**
- Create: `Palabra/Features/Mirroring/Sync/MirrorService.swift`, `Palabra/Features/Mirroring/Pairing/QRScannerView.swift`, `Palabra/Features/Settings/MirroringSettingsView.swift`, `PalabraTests/Mirroring/MirrorServiceTests.swift`
- Modify: `Palabra/App/AppEnvironment.swift` (new defaulted init parameter and stored property `mirror: MirrorService`), `Palabra/App/RootView.swift` (call the sync where `syncVocabularyCards()` runs on launch and on returning to the foreground), `Palabra/Features/Settings/SettingsView.swift` (a "Mirroring" section with a `NavigationLink` and identifier `mirroringSettingsLink`), `Palabra/Resources/ar.lproj/Localizable.strings`, `PalabraTests/App/LocalizationTests.swift` (`testArabicStringsHaveMirroringKeys`), `project.yml` and the Arabic `InfoPlist.strings` (camera text), `AGENTS.md`, `docs/features/mirroring.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `@MainActor @Observable final class MirrorService { init(secrets: MirrorSecretsStore = .init(), settings: MirrorSettingsStore = .init(), index: MirrorIndex = .standard(), session: URLSession = .shared, now: @escaping () -> Date = Date.init); var isPaired: Bool { get }; var computers: [MirrorComputer] { get }; var enabled: Bool { get set }; private(set) var lastSyncAt: Date?; private(set) var lastError: MirrorSyncError?; private(set) var syncing: Bool; func makePairingSession(link: PairingLink) -> MirrorPairingSession; func sync(records: [MirrorRecord], force: Bool = false) async; func remove(computerID: String) async; func turnOffAndForget() }` and `enum MirrorSyncError: Equatable { case offline, rejected /* 401 */, rateLimited, other }`. `sync` does nothing unless paired and `enabled` (or `force`), skips when the last sync was under 30 seconds ago (unless `force`), runs one push of `kinds: ["word"]`, updates `lastSyncAt` and `lastError`, and never throws. `turnOffAndForget` clears secrets, index and settings locally (the server's data stays; the settings screen says so). `AppEnvironment` gets `func mirrorSyncIfEnabled(force: Bool = false) async` that calls `mirror.sync(records: mirrorWordRecords(), force:)`.

- [ ] **Step 1: Write failing tests** `MirrorServiceTests` (temp index file, test Keychain account, `MockURLProtocol`): unpaired `sync` sends nothing; paired and enabled `sync` pushes and sets `lastSyncAt`; a second `sync` within 30 seconds (stub clock) sends nothing, with `force: true` it sends (nothing changed, so still no PUT but `lastSyncAt` updates); a 401 sets `lastError = .rejected` and keeps `lastSyncAt` unchanged; offline sets `.offline`; `remove(computerID:)` sends `DELETE` with the owner bearer and removes the computer locally only on success; `turnOffAndForget` leaves `isPaired == false`, an empty index file and no stored secrets; a launch with `enabled == false` (the default) never touches the network.
- [ ] **Step 2: Implement** `MirrorService` and the `AppEnvironment` additions (follow how existing defaulted services are injected; existing `AppEnvironment(...)` call sites in tests must compile unchanged). In `RootView`, run `Task { await environment.mirrorSyncIfEnabled() }` next to the existing launch/foreground sync calls.
- [ ] **Step 3: Implement `QRScannerView`** (`UIViewRepresentable` over `AVCaptureSession` with an `AVCaptureMetadataOutput` for `.qr`, calls `onCode(String)` once per distinct code, stops the session when dismissed; shows the permission-denied state with a button to open Settings) and **`MirroringSettingsView`**: sections Status (paired or not, last sync time, Sync Now, a plain error line for `MirrorSyncError`), Computers (name, paired date, swipe/menu Remove with confirmation), Pair a Computer (opens the scanner in a full-screen cover; below the camera a text field "Paste the pairing link" feeding the same `PairingLink.parse`; on a parsed link show a sheet with the session: "Joining…", then the 4-digit code in large type with "Confirm" and "Cancel" and the sentence "Check that this computer shows the same code", then Done or a failure message per `Failure`), and a destructive "Turn Off and Forget" with a confirmation explaining that the encrypted copy stays on the Worker. A footer says what is sent, that it is encrypted, and that data is as fresh as the last time Palabra was open. Enable toggle `mirroringEnabledToggle`; identifiers `mirrorSyncNow`, `mirrorPairButton`, `mirrorConfirmButton`.
- [ ] **Step 4: Strings and permissions.** Every new visible string gets an Arabic entry (`Localizable.strings`) and a line in `testArabicStringsHaveMirroringKeys`, including each `Failure` and `MirrorSyncError` message. Change `NSCameraUsageDescription` in `project.yml` (and its Arabic `InfoPlist.strings`) to keep the existing meaning and add: "or scan the pairing code shown by Palabra on your computer".
- [ ] **Step 5: Docs.** `docs/features/mirroring.md`: how to pair (open the Worker address on the PC, Settings -> Mirroring -> Pair a Computer, compare the code on both screens), what is mirrored now (words), what is not yet, and the honest limits (foreground-only freshness, the page needs the network to load until phase 3, Cloudflare account owner is trusted). `AGENTS.md`: a Mirroring entry in Layout, the new frozen names (`mirror-secrets`, `mirrorSettings`, `Mirror/index.json`, Protocol v1 constants) and the rule "Features/Mirroring never imports Word/Deck/Card/ReviewNeed; AppEnvironment+Mirror is the boundary".
- [ ] **Step 6: Push, read CI** (iOS `ipa` and `tests` jobs, plus the `Mirror` workflow); fix compile errors and failing tests; commit in logical pieces (`feat(mirror): service and automatic push`, `feat(mirror): Settings screen and QR scanner`, `docs(mirror): ...`).
- [ ] **Step 7: Hand-verify and report.** With the Worker deployed (plan 1) the person pairs a real computer: open the Worker address, scan, compare codes, Confirm on the phone, "Codes match" on the PC, then see the words. Report which of these were not exercised by CI (camera, real browsers, real Worker) and that the Swift code was compiled by eye until CI ran.

---

## Self-review (against the spec)

- Phase 2 text: item sealing and ids with vectors shared by Swift and JS (Tasks 1-2); QR pairing with the match code confirmed on both sides (Tasks 3, 5, 8); push of the words (Tasks 6, 8); the page pulls, decrypts and lists them from its local copy (Task 7). Keys and sealing, the Pairing steps 1-4 and the web app's CSP/escaping/Arabic/tokens requirements are covered; revoke is on the phone (`remove(computerID:)`), key rotation is explicitly out of scope.
- Deliberately deferred (listed in Global Constraints): the service worker, other collections, manifest and rollback check, mailbox, live channel, typed-phrase pairing, PIN.
- Name consistency checked across tasks: `MirrorKeys`, `MirrorCrypto`, `MirrorClient`, `MirrorSecrets(Store)`, `MirrorSettings(Store)`, `MirrorRecord`, `MirrorIndex`, `MirrorPusher`, `MirrorPairingSession`, `MirrorService`, `PairingLink`; web `createApi`, `createPairing`, `openLocalDb`, `pullOnce`, `importDataKey`, `deriveItemId`.
