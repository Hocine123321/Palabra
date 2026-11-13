# Mirroring

Browse and use Palabra from a PC browser as an installable web app. The phone app stays the one real copy of the data and the only
place that decides anything. A browser is paired with the phone once; after that the phone pushes its data, encrypted, to the
person's own Cloudflare account, and the web app pulls it, keeps it for offline use, and sends changes back. It works when the
phone is locked, away or off.

Design: `docs/superpowers/specs/2026-11-07-mirroring-design.md`. Code: `worker/` (the Cloudflare Worker and its tests), `web/`
(the web app), `.github/workflows/mirror.yml`.

## Setup (once)

The Worker is deployed by GitHub Actions from this repository. Without the two secrets below the deploy is skipped and everything else passes.

1. Create a free Cloudflare account (cloudflare.com).
2. In the Cloudflare dashboard open My Profile, API Tokens, Create Token, and use the **Edit Cloudflare Workers** template.
3. Copy your **Account ID** (Workers & Pages overview page, right-hand side).
4. On github.com open the repository, Settings, Secrets and variables, Actions, and add two repository secrets:
   `CLOUDFLARE_API_TOKEN` (the token) and `CLOUDFLARE_ACCOUNT_ID` (the id).
5. Run the **Mirror** workflow by hand (Actions, Mirror, Run workflow), or push a change under `worker/` or `web/`.
6. Open the finished run: the deployed address (`https://palabra-mirror.<you>.workers.dev`) is in the run summary.

## API

JSON in and out; errors are `{"error": "<code>"}`; no CORS headers (same origin only); responses are `Cache-Control: no-store`.
A bearer is `Authorization: Bearer <deviceId>.<token>`; the server keeps only SHA-256 hashes of tokens.

| Route | Body, answer |
|---|---|
| `POST /api/mirrors` | `{deviceId, ownerTokenHash}`, 201 `{mirrorId, deviceId}` |
| `POST /api/pair/start` | 201 `{pairId, expiresAt}` |
| `GET /api/pair/<id>` | `{state, phonePub?, sealed?}` (`phonePub` from the join on, `sealed` only once); a reply is handed out once |
| `POST /api/pair/<id>/join` | `{phonePub}`, 200 `{}` |
| `POST /api/pair/<id>/reply` | `{sealed}`, 200 `{}` |
| `POST /api/pair/<id>/cancel` | 200 `{}` |
| `POST /api/m/<mirrorId>/devices` | owner only, `{deviceId, tokenHash}`, 201 `{}` |
| `GET /api/m/<mirrorId>/devices` | `{devices}` |
| `DELETE /api/m/<mirrorId>/devices/<deviceId>` | owner only, 200 `{}` |
| `PUT /api/m/<mirrorId>/items` | owner only, `{items: [{id, sealed, deleted?}]}`, 200 `{seq}`; all or nothing |
| `GET /api/m/<mirrorId>/items?since=&limit=` | `{items, seq, more}`; `seq` is the mirror's head, so continue a page from the last item's `seq`, never from `seq` |
| `GET /api/m/<mirrorId>/state` | `{seq, epoch}` |
| `POST /api/m/<mirrorId>/rotate` | owner only, body at most 16,384 bytes: `{epoch, remove, blobs}` with `epoch` = current + 1 (else `409 stale_epoch`), `remove` a browser id or `null`, `blobs` `{deviceId: base64url ≤ 2,048 chars}`. One transaction: removes `remove` and every browser without a blob, deletes every item, stores the blobs, sets the epoch; `seq` never goes down. 200 `{epoch, removed}`; 6 per hour |
| `GET /api/m/<mirrorId>/rotation` | any device: `{epoch, blob}` for the caller, `404` without one for the current epoch; not cacheable |

Limits (all in `worker/src/limits.js`): body 1,048,576 bytes; one sealed item 262,144 characters; 200 items per PUT; a list page
at most 200 items and about 900,000 sealed characters; 20,000 items and 50,000,000 sealed characters per mirror; 8 browsers per mirror; a pairing slot lives
120 seconds. Rates: 5 mirror creations per hour, 10 pairing starts and 20 joins per 10 minutes, 300 pairing polls per 10 minutes
(per address; an IPv6 address counts as its /64), 50 new mirrors per day in total; 120 item writes and 240 item reads per minute (per device).

## Pairing a computer (on the phone)

1. Open your Worker's address in the computer's browser. It shows a QR code.
2. Phone: Settings → Mirror to a Computer → Pair a Computer, and scan the code (or paste the link into "Paste the pairing link").
3. Both screens show a 4-digit code. Check they match, then tap Confirm on the phone and Yes on the computer.
4. The phone sends the library at once; after that it sends changes when Palabra opens and on Sync Now (at most every 30 seconds).

Remove a computer in the same screen: its token is revoked on the Worker first. "Turn Off and Forget" wipes the keys, the computer list and the push index from the phone; the encrypted copy stays on the Worker.

## What is mirrored

Each kind is one record per thing; the phone's own id is the record id.

| Kind | Record id | Content |
|---|---|---|
| `word` | word UUID | id, key, Spanish, translation, part of speech, category, tags, dates, the full lesson content |
| `deck` | deck UUID | name, `vocabulary`/`user`, created date, counts `{total, due, new}` and `countsAt` |
| `card` | card UUID | user decks only (the vocabulary deck comes from the words): front, back, due, reps, lapses, phase, created |
| `stats` | `stats` | reviewed today, streak, last seven days, `asOf` |
| `review` | need UUID | open Need Review items only: headword, translation, score, note, flag count, updated |
| `artifact` | artifact UUID | title, `spec`/`app`, version, updated, `blocks`. Spec tables and charts are resolved by the phone (a failed bind becomes an `error` block); an app is listed with `blocks: null`, its page is never sent |
| `chat` | `latest` | the most recently updated conversation: title, word, turn roles, texts, dates, status (newest turns kept within a text budget) |
| `lesson` | lesson id | title, summary, book, chapter, language, `pageIds`, terms, transcription notes |
| `lessonPage` | `<lessonId>/<pageId>` | number, title, date label, blocks in the lesson-file JSON shape (an image keeps only `alt` and `caption`) |

The page shows due counts, streak and scores exactly as the phone sent them, labelled with their `asOf`/`countsAt` time; it applies no rules of its own.

Never mirrored: pronunciation audio, image bytes, API keys, older chats, chat thumbnails, actions and error text, Lesson Studio drafts, the raw AI response, app artifact pages. A record over 262,144 sealed characters is skipped and reported, not truncated. A kind the phone could not build in one sync is left alone on the Worker; a kind built empty removes its items. A `409 mirror_full` from the Worker shows as "The Worker is full."

## Limits seen from the phone

200 items or about 900,000 characters per request; a `429` shows as "The Worker is busy"; `401` as "no longer accepts this phone"; no connection as "offline". `lastSyncAt` only moves on a successful push.

## Installing the web app

The page is an installable web app: open your Worker's address in Chrome or Edge and use the install button in the address bar (Safari: Share, Add to Dock). A service worker (`web/src/sw.js`, built into `dist/sw.js`) keeps the shell (`/`, `app.js`, `app.css`, the manifest and two icons) in a cache named `palabra-shell-<hash of those files>`, so the page opens offline and shows the saved copy. It never handles `/api/*`, other methods or other origins; a new deploy changes the hash, installs a new cache, and deletes the old one. If registering it fails, nothing else changes. The icons are made from the phone app's icon by `web/scripts/make-icons.py`.

## Screens in the web app

Hash routes: `#/words`, `#/words/<id>` (word details), `#/study`, `#/review`, `#/artifacts`, `#/artifacts/<id>`, `#/chat`, `#/books`, `#/books/<id>`; anything else opens the words list, and an id that no longer exists shows "That item is gone". `<id>` is the item id. Every screen has the navigation bar, a Refresh button and the freshness lines. Everything from the phone is a text node: an unknown block type shows its text (or its type name), a field of the wrong type is skipped, nothing throws. A book follows its own `language` for reading direction (an Arabic lesson is right to left in an English browser); the app chrome follows the browser. Spec artifact charts are drawn from numbers only (bars or one line) with the values also in a table below. Apps (HTML artifacts) are listed with "Open this on your phone".

## Trust model

- Cloudflare sees: that a mirror exists, how many encrypted items, their sizes, when they change and the IP addresses that connect.
  It cannot see their contents or even what kind of record each is.
- Whoever controls the person's Cloudflare account or GitHub repo can ship different JavaScript to the web app. That is the person.
  The web app ships no third-party scripts and a strict Content-Security-Policy (`web/public/_headers`).
- A stolen unlocked PC or browser profile exposes the local copy. Revoking a browser cuts it off from future data; it keeps what it already downloaded.

## Protocol v1

Normative. The vectors in `PalabraTests/Mirroring/Fixtures/mirror-vectors.json` are produced by `web/scripts/make-vectors.mjs`, re-derived independently by `web/scripts/verify-vectors.py` (run in CI), and reproduced by both the web crypto (`web/src/crypto.js`) and the phone (`MirrorCrypto.swift`).

- Base64url means unpadded (`A-Z a-z 0-9 - _`). Ids (`pairId`, `mirrorId`, `deviceId`) are 16 random bytes = 22 characters; tokens and the data key are 32 random bytes.
- `dataKey` (32 bytes) never leaves phone and paired browsers. Two keys are derived with HKDF-SHA-256, empty salt, length 32: `kAes` with info `"palabra-mirror-aes-v1"` and `kId` with info `"palabra-mirror-id-key-v1"`.
- **Item id** = base64url of the first 16 bytes of HMAC-SHA-256(`kId`, UTF-8 of `kind + "|" + recordId`) (22 characters).
- **Sealed item** = `iv(12 random) | AES-256-GCM(kAes) ciphertext | tag(16)`, associated data = UTF-8 of `"palabra-mirror-item-v1|" + itemId`; sent as base64url.
- **Item plaintext** = UTF-8 JSON `{"v":1,"k":<kind>,"r":<recordId>,"h":<content hash hex>,"g":<generation>,"d":<payload object>}`. `g` increases with every push that sends anything; the browser keeps the row with the higher `g`; only the phone computes `h`.
- **Pair keys:** ECDH P-256; public keys are raw uncompressed points (65 bytes, base64url = 87 characters); shared secret = the 32-byte X coordinate; `kPair` = HKDF-SHA-256(ikm = shared, salt = the 16-byte nonce, info = `"palabra-mirror-pair-v1"`, length 32), used as an AES-256-GCM key.
- **Match code** = the first 4 bytes of SHA-256(`browserPub | phonePub | nonce`) as a big-endian unsigned integer, modulo 10000, zero-padded to 4 digits.
- **Wrap** (phone -> browser) = `iv(12) | AES-256-GCM(kPair) | tag` over UTF-8 JSON `{"v":1,"mirrorId","deviceId","deviceToken","dataKey"}` (`dataKey` base64url), associated data = UTF-8 of `"palabra-mirror-wrap-v1|" + pairId`.
- **Generation:** a push's `g` = `max(index.generation + 1, whole seconds since 1970-01-01 UTC)`, so losing the phone's index file never makes it go backwards. The browser never lets a row replace one with a higher `g`.
- **Manifest item:** kind `"manifest"`, recordId `"manifest"`, id derived like any item. Payload `d` = `{"counts":{"<kind>":<integer >= 1>},"idsHash":"<64 lowercase hex>","pushedAt":"<ISO-8601 UTC, whole seconds>"}`. `idsHash` = lowercase hex SHA-256 of the item ids of every live item except the manifest, sorted by code point, joined with `"\n"` (an empty list hashes the empty string); `counts` has one entry per kind with live items (manifest excluded). The phone pushes it, in its own request after the data items, when a push sent or deleted anything, when the computed `idsHash` differs from the last manifest's, or when none went out in the last 600 seconds. Vectors: `manifest` and `empty` in the fixture.
- **What the page concludes:** `verified` (valid manifest; counts and `idsHash` equal the local copy), `incomplete` (valid manifest, they differ: something is withheld or still arriving), `unverified` (no manifest, or one that fails validation). A pull whose first page reports a head `seq` below the saved one, or that carries a manifest with a lower `g` than the saved one, is refused and nothing is applied.
- **QR link:** `https://<worker host>/#p=<pairId>&k=<browserPub>&n=<nonce>` (nonce 16 bytes). `http` is accepted only for `localhost` and `127.0.0.1`.
- **Bearer:** `Authorization: Bearer <deviceId>.<token>`; the server is only ever sent `sha256Hex(token)`.

## Not verified by CI

CI runs the Worker's logic on Node and bundles it with `wrangler deploy --dry-run`. The Cloudflare runtime itself (Durable Objects,
static assets, headers) is only exercised by the smoke test that runs after a real deploy (`worker/scripts/smoke.mjs`); with no
secrets that test does not run. Real browsers and the phone's camera are not exercised by CI. `web/scripts/e2e-local.mjs` drives real Chromium
by hand (pairing, the manifest states, a replayed server, the service worker offline); it needs Playwright and is not part of CI. Not yet tried
on real hardware: installing the app on a PC, Safari and Firefox service workers, scanning the QR code with the phone camera, a real Cloudflare Worker.

Known gaps (deferred): only words are mirrored so far (plan 3b adds the other collections); revoking a computer does not yet rotate the data key (plan 3c); there is no mailbox or live channel; a mirror is never deleted when idle; tombstones are never purged; unauthenticated probes of random mirror ids are not rate limited per address.
