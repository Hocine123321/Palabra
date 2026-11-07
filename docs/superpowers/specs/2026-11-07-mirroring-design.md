# Mirroring: Palabra in a browser, kept in sync from the phone through Cloudflare

Status: **design, approved in conversation 2026-11-07. Nothing here is built yet.** Supersedes
[the web companion design](2026-11-07-web-companion-design.md) (live relay, `file://` page, same-Wi-Fi pairing). The earlier work
on the `experimental` branch is the starting point, not thrown away: see "What happens to the `experimental` work".

## Intent

The person wants to browse and use Palabra from a PC browser as a native-feeling web app. The phone app stays the one real copy
of the data and the only place that decides anything. A browser is **paired** with the phone once; after that the phone pushes its
data, encrypted, to the person's own Cloudflare account, and the web app pulls it, keeps it for offline use, and sends changes
back. It must work when the phone is locked, away or off, which a live-only relay cannot do.

## Why the old design is replaced

- iOS cannot serve connections or sync in the background, so the app is only reachable while it is open in front.
- The old design made the page ask the phone for everything over a live relay. With the phone away the page had nothing to show
  except what it had cached, and "waiting for the phone / waiting for the browser" was the failure users actually met (several
  fixes on `experimental` chase it: seats by role, presence notices, heartbeats).
- `file://` pages cannot be a service-worker app, and whether a browser lets them reach the phone's address was never settled.
- The same-Wi-Fi rule was there to make up for a short typed code. With a strong pairing secret and server-side rate limits it is
  not needed, and a server cannot see anyone's Wi-Fi anyway.

The new shape: **the phone pushes, the browser pulls.** Reading never needs the phone to be present. Only changes that need the
phone (AI calls, anything that must run now) need a live link.

## Goals

1. **Read everything without the phone.** Library, Study, Need Review, Artifacts (pages), the most recent Chat conversation and
   the Books lessons (2D reading only) open from the browser's local copy and update from Cloudflare when online.
2. **Pair once, strongly.** The PC page shows a QR code; the phone scans it and the person confirms a 4-digit match code on both
   screens. No code to type, nothing guessable.
3. **End-to-end encrypted.** Cloudflare stores and forwards ciphertext only. Keys live on the phone and in the paired browsers.
   The Gemini key, the backup key and model settings never leave the phone.
4. **Changes from the web are queued, not lost.** The browser keeps an outbox and posts changes to a mailbox on Cloudflare. The
   phone applies them the next time it is open, and the phone wins conflicts.
5. **Live actions when the phone is open.** AI calls, sending a chat message and anything that spends quota or cannot be undone
   run only over a live link, never from a stored queue.
6. **An installable web app** (service worker, manifest) served from the person's own Worker over HTTPS, working offline.
7. **One switch and a clear status in the app**: Settings -> Mirroring (on/off, paired computers with revoke, last sync, "Sync now").
8. **The UI never blocks on the phone.** Presence is a small badge ("phone online", "last synced 14:32"), never a gate.

## Non-goals

- No account system and no Palabra-run server. The Worker is deployed into the person's own Cloudflare account.
- No change to what the phone stores or to any persisted name (bundle id, SwiftData entities, UserDefaults keys, Keychain
  accounts). Mirroring only adds new ones.
- No syncing while the app is suspended (iOS does not allow it); data is as fresh as the last time the app was open.
- No second copy of business rules in JavaScript. The phone decides; the page shows and asks.
- The 3D desk is not rebuilt for the web; Books is the 2D pages only. Editing lessons from the web is out of scope.
- No push notifications, no multi-user sharing.

## Anti-goals

- A server that can read the person's words, or spend their AI quota.
- Silent replay of a stale outbox: no queued delete or AI call ever fires without a live, confirmed connection.
- A page state that depends on who is connected ("waiting for ..." forever).
- A feature that quietly keeps the phone awake. Keep-awake is a visible, optional switch.
- Secrets in the repo, in logs, in the debug console or in the library backup file.

## Constraints

- **Cloudflare limits and prices change.** Confirm the current free-tier limits (Worker requests per day, Durable Object storage
  and request counts, R2 storage) when building. The design stays small enough for one person: text records, no audio by default.
- The repo is edited from a phone. Deploying must work from GitHub Actions with two repository secrets
  (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`), set once from the GitHub site. CI without the secrets skips the deploy.
- CI cannot run a real browser against a real Worker. Pure logic, crypto vectors, the Worker against a local test server and a
  fake phone are covered; the pairing on real devices is verified by the person and reported honestly.
- Repo rules apply: `Features/*` does not import `Word`, `Deck`, `Card` or `ReviewNeed` (data crosses from the App layer as plain
  values, like `examWords()`); new UI strings need Arabic keys; new `UserDefaults` keys and Keychain accounts only, tolerant
  decoders; camera permission wording changes (QR scanning) must still say what the camera is used for in Solve and Lesson Studio.

## Trust model, stated plainly

- Cloudflare sees: that a mirror exists, how many encrypted items, their sizes, when they change and the IP addresses that connect.
  It cannot see their contents or even what kind of record each is.
- Whoever controls the person's Cloudflare account or GitHub repo can ship different JavaScript to the web app. That is the person.
  The web app ships no third-party scripts and a strict Content-Security-Policy.
- A stolen unlocked PC or browser profile exposes the local copy. Mitigations: "Forget this computer", revoke from the phone, and
  (later) an optional PIN that encrypts the stored key.
- Revoking a browser cuts it off from future data. It keeps what it already downloaded.

## Design

### Pieces

```
relay/            the Worker (kept name): Durable Object "Mirror" (SQLite storage), REST + WebSocket, serves the web app as static assets
web/              the web app (UI, local store, outbox, crypto, sync), built to files the Worker serves
Palabra/Features/WebLink/   the phone side (folder name kept; user-facing name is "Mirroring")
Palabra/App/                the App-layer data source that turns Word/Deck/... into plain values for the snapshot
.github/workflows/          deploy-mirror.yml (Worker + web), tests for web/ and relay/ on every push
```

One Worker serves both the web app and the API, so there is one URL, no cross-origin rules and nothing else to host.

### Cloudflare side (one Durable Object per mirror)

SQLite-backed Durable Object `Mirror`, addressed by a random `mirrorId`:

| Table | Holds |
|---|---|
| `items` | `id` (opaque), `seq`, `sealed` (ciphertext), `deleted`. One row per record; an upsert replaces the row and gets the next `seq`. |
| `ops` | the mailbox: `opId`, `device`, `sealed`, `status` (pending / done), `result` (sealed) |
| `devices` | `deviceId`, `tokenHash` (SHA-256), `label` (sealed), `role` (owner / browser), `createdAt` |
| `pairing` | short-lived slots (2 minutes, single use) |

Endpoints (all JSON except the socket; every call after pairing carries `Authorization: Bearer <deviceToken>`):

| Call | Who | Does |
|---|---|---|
| `POST /api/pair/start` | browser | creates a pairing slot, returns `pairId` |
| `POST /api/pair/<id>/join` | phone | posts the phone's public key; creates the mirror on first use |
| `GET /api/pair/<id>` | browser | long-polls for the phone's reply (wrapped keys), then the slot is deleted |
| `PUT /api/items` | owner | batch upsert / tombstone, at most about 1 MB per request |
| `GET /api/items?since=<seq>` | any device | changed rows since `seq`, paged |
| `POST /api/ops`, `GET /api/ops?after=` , `POST /api/ops/<id>/result` | browser / owner | the mailbox |
| `GET /api/devices`, `DELETE /api/devices/<id>` | owner | list and revoke |
| `GET /live?role=app|web` (WebSocket, hibernating) | any device | the live channel (see below) |

Limits that exist from day one: request size caps, per-IP rate limits on `/api/pair/*`, per-device rate limits, a cap on items and
ops. The server stores no plaintext and logs no bodies.

### Keys and sealing

- ECDH P-256 (WebCrypto and CryptoKit both have it), HKDF-SHA-256, AES-256-GCM. No custom primitives.
- The phone makes one random 256-bit **`dataKey`** per mirror. Every stored item is `iv(12) | AES-GCM(dataKey, plaintext)` with
  associated data `schemaVersion | seq | itemId`, so the server cannot swap or replay an item under another identity.
- **Item ids are opaque**: `id = HMAC-SHA-256(dataKey, kind | recordId)` truncated. The server cannot tell words from decks. The
  kind and the record id are inside the sealed plaintext.
- A sealed **manifest** item (counts per kind, a hash of the ids, a `generation` that only goes up, the phone's `pushedAt`)
  lets the browser notice a server that withholds items or serves an older state: it refuses a generation lower than the highest
  it has seen.
- Live frames keep the existing stream format and epoch/counter rules from the `experimental` work (they were pinned by shared
  test vectors and fixed a real replay bug). Stored items do **not** use counters: they are independent and random-access.

### Pairing (first computer, and every later one)

1. The person opens the Worker URL on the PC. The page makes an ECDH key pair and calls `/api/pair/start`. It shows a QR code
   holding `https://<worker>/#p=<pairId>&k=<browserPublicKey>&n=<nonce>` (and the page's own origin, so the phone needs no server
   setting).
2. Settings -> Mirroring -> **Pair a computer** opens the camera. The phone scans, makes its own key pair, derives
   `kPair = HKDF(ECDH, salt = nonce, "palabra-mirror-pair-v1")` and posts its public key to the slot.
3. Both screens show a **4-digit match code** (first digits of SHA-256 of both public keys and the nonce). The person confirms it
   on the phone. A different code means someone interfered: tap Cancel and nothing is saved.
4. On Confirm the phone sends, sealed under `kPair`: `dataKey`, `mirrorId`, a new `deviceToken` and a per-device wrap key. The slot
   is deleted. The browser stores them (the `dataKey` as a non-extractable `CryptoKey`) and starts pulling.
5. Paired computers are listed in the app with name and last seen, each with **Revoke**. Revoking deletes its device row and
   **rotates the `dataKey`**: the phone seals a fresh key to each remaining computer, re-seals the items, and the old key stops
   working for new data.

Fallback when scanning is not possible (later phase): the page shows an 8-word phrase (about 88 bits) that is the pairing secret;
the person types it into the app. It is strong enough without a PAKE because of the slot's single use and the server rate limit.

### Syncing data (phone -> browser)

- The phone builds the mirror from the same read paths the old web link already uses (`WebLinkDispatcher` read allow-list,
  `WebArtifactReader`, `WebChatBooksReader`), through a data source in the App layer. Collections: words (with sections and tags),
  decks and due counts, Need Review, stats, Artifact pages (resolved by the phone with its own binder; apps are listed but never
  shipped), the most recent chat conversation, and the Books lessons (small JSON: pushed up front, not on visit).
- The phone keeps a local **index** (`itemId -> content hash`) in a small file in Application Support. A push sends only the
  items whose hash changed and tombstones for deleted records. Words have no stored version (and none is added), so the content
  hash is the revision.
- Push triggers: app launch, return to the foreground, a debounced change while the app is open and Mirroring is on, and the
  **Sync now** button. Nothing runs while the app is suspended.
- The browser pulls `since=<its last seq>`, opens and applies items in one local transaction (IndexedDB), then verifies the
  manifest. It shows "last synced <time from the manifest>" and the phone-online badge.
- Not mirrored by default: pronunciation audio (large; the browser's own speech synthesis is the fallback), API keys, settings
  that are secrets, older chat conversations, the Lesson Studio drafts. Audio can become an opt-in R2 upload later.

### Changes from the web (browser -> phone)

- Allowed changes are the same short **allow-list** as on the phone today (`WebLinkDispatcher.writeAllowList`): add words, place
  a word in a section or tags, flag for review, and the first new ones (such as grading a flashcard). The phone is the one that
  enforces it; the page checks too, again at send time.
- The browser keeps the outbox (existing `outbox.js`: ids, order, retries, "needs your review"). Posting to `/api/ops` is the
  "send"; the op waits there until the phone is open.
- The phone drains the mailbox on foreground and on connect: for each op it checks shape and allow-list, drops repeats by
  `opId` (a small capped file of applied ids, so restarts are safe), checks the conflict token for `words.place` (the existing
  `PlacementToken`), applies it through the capability registry, writes a sealed result, and pushes the changed items.
- A rejected op appears in the browser under **Needs your review** with a plain reason; the person retries, edits or drops it.
- **Never queued:** `ai.generate`, chat sends, deletes, `storage.*`. They only run over the live channel.

### Live channel

A hibernating WebSocket in the same Durable Object forwards frames between the connected devices. Used only for live-only actions
(AI add-word, chat, confirmed delete) and for the presence badge. If the phone is not there, the browser says so at the button and
does nothing; it does not queue. The frames use the existing sealed stream format and the 256 KB frame limit with chunking.

### The web app

- Reused from `experimental`: `web/src/ui/*` (shell, render, model, strings, tokens, artifacts, chat and books views, the debug
  console), `cache.js`, `sync.js`, `outbox.js`, `writes.js`, the Arabic/RTL strings test, and the test that fails when
  `tokens.css` drifts from `Theme.swift`.
- Changes: it is built into **separate files** (not one inline file) so a strict CSP (`script-src 'self'`) can apply; a service
  worker caches the shell so it opens offline; the first screen is "Pair this computer" (QR) when nothing is stored, otherwise the
  local copy; the "waiting for the phone" states are removed in favour of the badge.
- Same layout, colours, typography and flows as the app, except iOS-only elements (haptics, glass materials, the SceneKit desk).

### Phone side

- `Features/WebLink` keeps its folder and its persisted names. User-facing text says **Mirroring**.
- New: `MirrorClient` (REST + live socket, reusing `ReconnectBackoff`), `MirrorCrypto` (CryptoKit), `MirrorIndex` (diff of what was
  pushed), `MirrorPairing` (QR scanner with AVFoundation, match code, key wrap), `MirrorOpsRunner` (drains the mailbox),
  `MirrorSettings` (new key, tolerant decoder), the Settings -> Mirroring screen.
- Secrets (`dataKey`, `ownerToken`, device wrap keys) live in new Keychain accounts. They are never written to the library
  backup, logs or the debug console.

## What happens to the `experimental` work

`experimental` holds about 9,500 lines for the old design (phases 1-6: pairing hop, relay, read-only UI, offline cache, outbox,
artifacts, chat and books, auto-pair, debug console), with tests and a green CI run. Phase 0 audits it file by file; the working
assumption is:

| Keep and adapt | Replace | Delete when replaced |
|---|---|---|
| `web/src/ui/*`, `cache.js`, `sync.js` (state machine), `outbox.js`, `writes.js`, `debug-*`, tests for tokens/strings/render | the transport: a live two-seat relay becomes the store-and-forward Mirror DO | `LocalPairingListener`, `LocalAddress`, `PairingHTTP`, `PairingLockout` (phone side), `LobbyClient` |
| `LinkCrypto` and `LinkChunking` (for the live channel), `WebLinkDispatcher`, `WebArtifactReader`, `WebChatBooksReader`, `RecentActions`, `ReconnectBackoff`, `PlacementToken` | pairing: LAN hop + lobby + trust prompt become QR + match code | `relay/src/lobby.js`, `web/src/auto-pair.js`, `trust-crypto.js`, `TrustCrypto`/`TrustGate` (their device list moves into the `devices` table), `BrowserPresence` |

## Calls made (reversible)

- Store-and-forward with E2E encryption, replacing "the relay stores nothing". The data on Cloudflare is ciphertext.
- Web app served by the person's Worker over HTTPS instead of a `file://` page. Costs one deploy setup; removes the local-network
  uncertainty and enables offline installable use.
- QR plus match code is the main pairing; a typed phrase is a later fallback. Same-Wi-Fi is dropped as a rule.
- Books lessons are pushed up front (they are small text) instead of cached on visit. Only the 2D pages; no 3D desk.
- Chat: only the most recent conversation is mirrored. Audio is not mirrored by default.
- The words' revision is a content hash; no new stored version field is added to `Word`.
- Folder and persisted names stay `WebLink`; only visible strings say "Mirroring".

## Phases (CI green and reported after each; each is shippable)

0. **Land and audit.** Decide how `experimental` reaches `main` (merge it, then evolve), run its web and relay tests in CI, write
   the keep/replace/delete list from the actual files. Rename user-facing strings to "Mirroring". *Needs from the person:* nothing.
1. **The Worker.** `Mirror` Durable Object (items, ops, devices, pairing), REST and live socket, static assets, limits, tests against a
   local server with a fake phone, and `deploy-mirror.yml`. *Needs from the person (once):* a free Cloudflare account, an API
   token from the "Edit Cloudflare Workers" template, the account id, both added as GitHub repository secrets.
2. **Pairing and the first records.** Item sealing and ids with shared test vectors (Swift and JS), QR pairing with the match code,
   push of the words collection, the page pulls, decrypts and lists them offline. This proves every hard part end to end.
3. **Full read sync.** All collections, incremental diff push, manifest and rollback check, service worker and installable app,
   the freshness badge, revoke and key rotation. Remove the old LAN pairing and lobby.
4. **Mailbox.** The outbox posts to `/api/ops`; the phone drains, applies, answers and re-pushes; the review list works.
5. **Live channel.** Presence badge, AI add-word, chat send, confirmed delete, flashcard grading with live feedback.
6. **More surfaces.** Artifact apps in a sandboxed iframe (own design review: no same-origin, CSP on the frame, a message bridge that
   forwards only that artifact's granted capabilities); Books 2D polish.
7. **Hardening.** Typed-phrase pairing, optional PIN for the stored key, audio opt-in, abuse limits tuned, docs
   (`docs/features/mirroring.md`, AGENTS.md, REVIEW.md), a plain "what is not verified" note.

## Tests

- **Crypto:** fixed vectors shared by `PalabraTests/WebLink` and `web/test` (seal/open, id derivation, wrap, match code, tamper and
  wrong-AAD failures), as the old link did.
- **Worker:** local server tests with a fake phone and a fake browser: pairing slot single use and expiry, rate limits, `since`
  paging, tombstones, op idempotency, revoke, rollback refusal. No plaintext ever appears in stored rows (asserted).
- **Phone:** `MirrorIndex` diffs, ops runner (allow-list, repeat by `opId`, conflict via `PlacementToken`), settings decoding,
  Arabic strings for every new key.
- **Web:** sync state machine, outbox ordering and send-time re-check, offline start from the local copy, XSS escaping on every
  screen, tokens and strings tests (existing).
- **Not covered by CI:** the camera scan, real Safari/Chrome service workers, real Cloudflare. The person verifies pairing on a real
  phone and PC, and the report says so.

## Open questions

- A custom domain, or the default `*.workers.dev` address?
- Web framework: keep the existing hand-written modules (smallest) or move to a small library as the screens multiply.
- Whether pronunciation audio is worth an opt-in R2 upload, given the size and the phone's data use.
- Whether to gate the Worker's pairing start behind an optional setup secret, beyond rate limits, to stop strangers burning the
  free quota (they cannot read or pair anything).
- How long unprocessed ops and results are kept (suggested: 30 days, capped).
