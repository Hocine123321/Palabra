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
| `GET /api/pair/<id>` | `{state, phonePub?, sealed?}`; a reply is handed out once |
| `POST /api/pair/<id>/join` | `{phonePub}`, 200 `{}` |
| `POST /api/pair/<id>/reply` | `{sealed}`, 200 `{}` |
| `POST /api/pair/<id>/cancel` | 200 `{}` |
| `POST /api/m/<mirrorId>/devices` | owner only, `{deviceId, tokenHash}`, 201 `{}` |
| `GET /api/m/<mirrorId>/devices` | `{devices}` |
| `DELETE /api/m/<mirrorId>/devices/<deviceId>` | owner only, 200 `{}` |
| `PUT /api/m/<mirrorId>/items` | owner only, `{items: [{id, sealed, deleted?}]}`, 200 `{seq}`; all or nothing |
| `GET /api/m/<mirrorId>/items?since=&limit=` | `{items, seq, more}`; `seq` is the mirror's head, so continue a page from the last item's `seq`, never from `seq` |
| `GET /api/m/<mirrorId>/state` | `{seq}` |

Limits (all in `worker/src/limits.js`): body 1,048,576 bytes; one sealed item 262,144 characters; 200 items per PUT; a list page
at most 200 items and about 900,000 sealed characters; 20,000 items and 50,000,000 sealed characters per mirror; 8 browsers per mirror; a pairing slot lives
120 seconds. Rates: 5 mirror creations per hour, 10 pairing starts and 20 joins per 10 minutes, 300 pairing polls per 10 minutes
(per address; an IPv6 address counts as its /64), 50 new mirrors per day in total; 120 item writes and 240 item reads per minute (per device).

## Trust model

- Cloudflare sees: that a mirror exists, how many encrypted items, their sizes, when they change and the IP addresses that connect.
  It cannot see their contents or even what kind of record each is.
- Whoever controls the person's Cloudflare account or GitHub repo can ship different JavaScript to the web app. That is the person.
  The web app ships no third-party scripts and a strict Content-Security-Policy (`web/public/_headers`).
- A stolen unlocked PC or browser profile exposes the local copy. Revoking a browser cuts it off from future data; it keeps what it already downloaded.

## Not verified by CI

CI runs the Worker's logic on Node and bundles it with `wrangler deploy --dry-run`. The Cloudflare runtime itself (Durable Objects,
static assets, headers) is only exercised by the smoke test that runs after a real deploy (`worker/scripts/smoke.mjs`); with no
secrets that test does not run. Real browsers and the phone's camera are not exercised by CI.

Known gaps (deferred): a mirror is never deleted when idle; tombstones are never purged; unauthenticated probes of random mirror ids are not rate limited per address.
