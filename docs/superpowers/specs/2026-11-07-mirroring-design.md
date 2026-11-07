# Mirroring: Palabra in a browser, kept in sync from the phone through Cloudflare

Status: **design, approved in conversation 2026-11-07. Nothing here is built yet.** Everything is written new on `main`; no
earlier prototype is reused or carried over.

## Intent

The person wants to browse and use Palabra from a PC browser as a native-feeling web app. The phone app stays the one real copy
of the data and the only place that decides anything. A browser is **paired** with the phone once; after that the phone pushes its
data, encrypted, to the person's own Cloudflare account, and the web app pulls it, keeps it for offline use, and sends changes
back. It must work when the phone is locked, away or off, which a live-only relay cannot do.

## Shape

**The phone pushes, the browser pulls.** Reading never needs the phone to be present, because iOS cannot serve connections or sync
in the background. Only changes that need the phone (AI calls, anything that must run now) need a live link. The web app is served
over HTTPS by the person's own Worker, so it is an installable, offline-capable web app, and pairing needs no network proximity:
a strong pairing secret and server-side rate limits replace any same-Wi-Fi rule.

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
worker/           the Worker: Durable Objects "Mirror" and "Gate" (SQLite storage), REST (later also a WebSocket), serves the web app as static assets
web/              the web app (UI, local store, outbox, crypto, sync), built to files the Worker serves
Palabra/Features/Mirroring/   the phone side
Palabra/App/                the App-layer data source that turns Word/Deck/... into plain values for the snapshot
.github/workflows/          deploy-mirror.yml (Worker + web), tests for web/ and relay/ on every push
```

One Worker serves both the web app and the API, so there is one URL, no cross-origin rules and nothing else to host.

### Cloudflare side

Two SQLite-backed Durable Objects. **`Gate`** is a single instance that holds pairing slots and per-IP rate counters.
**`Mirror`** is one instance per mirror, addressed by a random `mirrorId`:

| Table | Holds |
|---|---|
| `items` | `id` (opaque), `seq`, `sealed` (ciphertext), `deleted`. One row per record; an upsert replaces the row and gets the next `seq`. |
| `devices` | `deviceId`, `tokenHash` (SHA-256 of a token the client generated; the server never sees the token), `role` (owner / browser), `createdAt`, `lastSeen` |
| `ops` | added with the mailbox phase: `opId`, `device`, `sealed`, `status` (pending / done), `result` (sealed) |

`Gate` holds `slots` (pairing: `pairId`, `phonePub`, `sealed` reply, state, expiry; two minutes, single use) and `rates` (counters).

Endpoints (all JSON except the socket; every call after pairing carries `Authorization: Bearer <deviceToken>`):

| Call | Who | Does |
|---|---|---|
| `POST /api/mirrors` | phone | creates a mirror from the hash of an owner token the phone generated; returns `mirrorId`, `deviceId` |
| `POST /api/pair/start` | browser | creates a pairing slot, returns `pairId` |
| `POST /api/pair/<id>/join` | phone | posts the phone's public key (one join per slot) |
| `GET /api/pair/<id>` | browser | polls the slot: waiting, joined (with the phone's key), replied (with the sealed keys), cancelled |
| `POST /api/pair/<id>/reply`, `/cancel` | phone / either | deposits the sealed keys; ends the slot |
| `POST /api/m/<mirrorId>/devices`, `GET`, `DELETE .../<deviceId>` | owner | register a browser (by token hash), list, revoke |
| `PUT /api/m/<mirrorId>/items` | owner | batch upsert / tombstone, at most about 1 MB per request |
| `GET /api/m/<mirrorId>/items?since=<seq>` | any device | changed rows since `seq`, paged |
| `GET /api/m/<mirrorId>/state` | any device | the latest `seq` (also checks the token) |
| mailbox (`/ops`) and live channel (`/live`, a hibernating WebSocket) | | added in their own phases |

Limits that exist from day one: request size caps, per-IP rate limits on `/api/pair/*` and `/api/mirrors`, per-device rate limits, a
cap on items and devices. The server stores no plaintext and logs no bodies.

### Keys and sealing

- ECDH P-256 (WebCrypto and CryptoKit both have it), HKDF-SHA-256, AES-256-GCM. No custom primitives.
- The phone makes one random 256-bit **`dataKey`** per mirror. Every stored item is `iv(12) | AES-GCM(dataKey, plaintext)` with
  associated data `"palabra-mirror-item-v1|" + itemId`, so the server cannot move an item to another identity. The plaintext
  carries the record's `kind`, `recordId`, content hash and a `generation` that only goes up; the server assigns `seq` after
  sealing, so `seq` is not part of the sealing.
- **Item ids are opaque**: `id = HMAC-SHA-256(dataKey, kind | recordId)` truncated. The server cannot tell words from decks. The
  kind and the record id are inside the sealed plaintext.
- A sealed **manifest** item (counts per kind, a hash of the ids, a `generation` that only goes up, the phone's `pushedAt`)
  lets the browser notice a server that withholds items or serves an older state: it refuses a generation lower than the highest
  it has seen.
- Live frames (live-channel phase) get their own stream format with per-connection random stream ids and counters, so a reconnect is
  never mistaken for a replay. Stored items do **not** use counters: they are independent and random-access.

### Pairing (first computer, and every later one)

1. The person opens the Worker URL on the PC. The page makes an ECDH key pair and calls `/api/pair/start`. It shows a QR code
   holding `https://<worker>/#p=<pairId>&k=<browserPublicKey>&n=<nonce>`; the origin in the link means the phone needs no server
   setting.
2. Settings -> Mirroring -> **Pair a computer** opens the camera. The phone scans, makes its own key pair, derives
   `kPair = HKDF(ECDH, salt = nonce, "palabra-mirror-pair-v1")` and posts its public key to the slot.
3. Both screens show a **4-digit match code** (from SHA-256 of both public keys and the nonce). **Both sides need a human yes:**
   the phone releases the keys only after the person taps Confirm, and the browser accepts them only after the person clicks
   "Codes match". A different code, or a scan that fails because someone else joined the slot first, means: Cancel, nothing is saved.
4. On Confirm the phone creates the mirror if it has none (it generates the owner token and sends only its hash), registers the
   browser as a device (a token the phone generated, again sent as a hash) and deposits, sealed under `kPair`, the `dataKey`,
   `mirrorId`, `deviceId` and device token. The slot is deleted once read. The browser stores them (the `dataKey` as a
   non-extractable `CryptoKey`) and starts pulling.
5. Paired computers are listed in the app with name and last seen, each with **Revoke**. Revoking deletes its device row and
   **rotates the `dataKey`** (hardening phase): the phone seals a fresh key to each remaining computer, re-seals the items, and the old
   key stops working for new data. Until rotation exists, revoking still cuts the computer off, because it can no longer fetch.

Fallback when scanning is not possible (later phase): the page shows an 8-word phrase (about 88 bits) that is the pairing secret;
the person types it into the app. It is strong enough without a PAKE because of the slot's single use and the server rate limit.

### Syncing data (phone -> browser)

- The phone builds the mirror through a data source in the App layer (`AppEnvironment+Mirror.swift`, the same pattern as
  `examWords()`), so `Features/Mirroring` never imports `Word` and friends. Collections: words (with sections and tags),
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

- Allowed changes are a short **allow-list** held by the phone (the page checks too, again at send time): add words, place a word in a
  section or tags, flag for review, and the first new ones (such as grading a flashcard).
- The browser keeps the outbox (ids, order, retries, "needs your review"). Posting to `/api/ops` is the
  "send"; the op waits there until the phone is open.
- The phone drains the mailbox on foreground and on connect: for each op it checks shape and allow-list, drops repeats by
  `opId` (a small capped file of applied ids, so restarts are safe), checks the conflict token for `words.place` (a plain-text placement token of section and tags, compared on the phone), applies it through the capability registry, writes a sealed result, and pushes the changed items.
- A rejected op appears in the browser under **Needs your review** with a plain reason; the person retries, edits or drops it.
- **Never queued:** `ai.generate`, chat sends, deletes, `storage.*`. They only run over the live channel.

### Live channel

A hibernating WebSocket in the same Durable Object forwards frames between the connected devices. Used only for live-only actions
(AI add-word, chat, confirmed delete) and for the presence badge. If the phone is not there, the browser says so at the button and
does nothing; it does not queue. The frames are sealed with the live-channel format above and capped in size, with chunking for larger replies.

### The web app

- Plain modules, no framework to start (see Open questions), bundled by a small build script into separate files (`app.js`,
  `app.css`) so a strict CSP (`script-src 'self'`, no inline styles or scripts) applies. WebCrypto for all cryptography; IndexedDB
  for the local copy; no third-party scripts except a QR generator bundled at build time.
- First screen: "Pair this computer" (QR). Afterwards it opens straight onto the local copy and updates from Cloudflare.
- Same layout, colours, typography and flows as the app, except iOS-only elements (haptics, glass materials, the SceneKit desk).
  A test fails if the colour tokens drift from `Theme.swift`. Every phone-supplied string is escaped; a test feeds markup through
  every screen. English and Arabic (right to left), following the browser language.
- A service worker (phase 3) caches the shell so it opens offline. Presence is a badge, never a gate.

### Phone side

- `Features/Mirroring` (user-facing name **Mirroring**): `MirrorCrypto` (CryptoKit), `MirrorClient` (REST over URLSession),
  `MirrorSecrets` (Keychain), `MirrorSettings` (new `UserDefaults` key, tolerant decoder), `MirrorPairing` (QR link parsing,
  pairing session, match code, key wrap), `MirrorIndex` (what was pushed) and `MirrorPusher`, the Settings -> Mirroring screen.
  Later phases add the mailbox runner and the live client.
- Secrets (`dataKey`, owner token, device tokens) live in new Keychain accounts. They are never written to the library backup, logs
  or the debug console. Persisted names added: Keychain account `mirror-secrets`, `UserDefaults` key `mirrorSettings`, the file
  `Application Support/Mirror/index.json`; once shipped they are frozen like the rest.

## Calls made (reversible)

- Store-and-forward with E2E encryption, replacing "the relay stores nothing". The data on Cloudflare is ciphertext.
- Web app served by the person's Worker over HTTPS instead of a `file://` page. Costs one deploy setup; removes the local-network
  uncertainty and enables offline installable use.
- QR plus match code is the main pairing; a typed phrase is a later fallback. Same-Wi-Fi is dropped as a rule.
- Books lessons are pushed up front (they are small text) instead of cached on visit. Only the 2D pages; no 3D desk.
- Chat: only the most recent conversation is mirrored. Audio is not mirrored by default.
- The words' revision is a content hash; no new stored version field is added to `Word`.
- Pairing slots and rate counters live in one `Gate` Durable Object; mirrors are created by the phone, which also generates every token, so the server only ever holds token hashes.

## Phases (CI green and reported after each; each is shippable)

1. **The Worker.** `Gate` and `Mirror` Durable Objects (pairing slots, mirrors, devices, items), REST, static assets with a strict CSP,
   limits, tests, and the deploy workflow with a post-deploy smoke test. *Needs from the person (once):* a free Cloudflare account, an
   API token from the "Edit Cloudflare Workers" template, the account id, both added as GitHub repository secrets
   (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`).
2. **Pairing and the first records.** Item sealing and ids with vectors shared by Swift and JS, QR pairing with the match code on both
   sides, push of the words collection, and the page pulls, decrypts and lists them from its local copy. Proves every hard part.
3. **Full read sync.** All collections, incremental diff push, manifest and rollback check, the service worker and installable app,
   the freshness badge, revoke with key rotation.
4. **Mailbox.** The Worker's `/ops`, the browser outbox, the phone's runner (allow-list, repeats by `opId`, conflict check), the review list.
5. **Live channel.** The Worker's WebSocket, presence badge, AI add-word, chat send, confirmed delete, flashcard grading.
6. **More surfaces.** Artifact apps in a sandboxed iframe (own design review: no same-origin, CSP on the frame, a bridge that forwards
   only that artifact's granted capabilities); Books 2D polish.
7. **Hardening.** Typed-phrase pairing, optional PIN for the stored key, audio opt-in, abuse limits tuned, docs, a plain "what is not
   verified" note.

Plans: [phase 1](../plans/2026-11-07-mirroring-1-worker.md), [phase 2](../plans/2026-11-07-mirroring-2-pairing-first-records.md).

## Tests

- **Crypto:** fixed vectors in one JSON file read by both `PalabraTests/Mirroring` and `web/test` (seal/open, id derivation, key
  agreement, match code, wrap, tamper and wrong-AAD failures), and checked once with an independent Python implementation.
- **Worker:** local server tests with a fake phone and a fake browser: pairing slot single use and expiry, rate limits, `since`
  paging, tombstones, op idempotency, revoke, rollback refusal. No plaintext ever appears in stored rows (asserted).
- **Phone:** `MirrorIndex` diffs and the requests actually sent (bodies inspected with `MockURLProtocol`), the pairing session, settings
  decoding, Arabic strings for every new key.
- **Web:** pairing state machine, pull and decrypt, rendering from the local copy, XSS escaping on every screen, tokens and strings tests.
- **Not covered by CI:** the camera scan, real Safari/Chrome service workers, real Cloudflare. The person verifies pairing on a real
  phone and PC, and the report says so.

## Open questions

- A custom domain, or the default `*.workers.dev` address?
- Web framework: plain modules to start; revisit if the screens multiply.
- Whether pronunciation audio is worth an opt-in R2 upload, given the size and the phone's data use.
- Whether to gate the Worker's pairing start behind an optional setup secret, beyond rate limits, to stop strangers burning the
  free quota (they cannot read or pair anything).
- How long unprocessed ops and results are kept (suggested: 30 days, capped).
