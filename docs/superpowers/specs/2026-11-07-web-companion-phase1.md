# Web companion, phase 1: link proof

Branch: `experimental`. Parent: [web companion design](2026-11-07-web-companion-design.md). No web UI yet.

## What phase 1 proves

1. A page can pair with the phone over a **direct local connection** (the same-Wi-Fi proof), with a wrong code refused and a growing lockout.
2. The phone and the page then meet at a **relay** that sees only opaque bytes.
3. An **encrypted ping** goes page -> relay -> phone, and the **ack** comes back.
4. The open question: **can a `file://` page reach the phone's local address?**

## Pieces

| Where | What |
|---|---|
| `relay/` | Cloudflare Worker + Durable Object (`src/worker.js`), the pure `Room` logic (`src/room.js`), tests with a real WebSocket server |
| `web/src/link-crypto.js` | The crypto, WebCrypto only |
| `web/src/link-client.js` | Pairing hop + relay client |
| `web/link-proof.html` | The bare test page (no app UI) |
| `Palabra/Features/WebLink/` | `LinkCrypto`, `PairingLockout`, `PairingService`, `PairingHTTP`, `LocalPairingListener`, `RelayClient`, `WebLinkController`, `WebLinkSettings` |
| `Palabra/Features/Settings/WebAccessView.swift` | Settings > Web Access |

## Protocol v1

**Local hop** (HTTP on port 47615, only while Pair a Browser is open, only Wi-Fi, only private source addresses):

- `GET /hello` -> `{protocol, nonce}`: a fresh 16-byte nonce, valid 120 s, usable once (so one nonce is one guess).
- `POST /pair {nonce, proof}`:
  - `proof = HMAC-SHA256(HKDF(code, salt=nonce, "palabra-proof-v1"), nonce)`. The code is never sent.
  - Right: `200 {iv, sealed}`, where `sealed = AES-256-GCM(HKDF(code, nonce, "palabra-wrap-v1"), secret, aad=nonce)`. Only someone who knows the code can open the session secret.
  - Wrong: `400 {error:"wrong", triesLeft}`. Lockout: `423 {error:"locked", seconds}`.
- Lockout: 5 wrong -> 30 s, then 2 min, 10 min, 1 h (cap). Kept in the app (UserDefaults `webLinkLockout`), so reloading the page resets nothing. A successful pairing resets it.
- The code is at least 6 ASCII digits, shown only while pairing is open, and each opening makes a **new secret**.

**Relay** (`wss://<worker>/r/<room>`):

- `room = hex(HKDF(secret, "palabra-room-v1", 16))`. The relay never sees the code or the secret.
- A room holds 2 sockets; a third is closed (4001). Binary frames only (4004), at most 256 KB (4002), at most 50 frames/s per socket with a burst of 100 (4003). Nothing is stored or logged.

**Frames:** `iv(12) | counter(8, big endian) | AES-256-GCM(HKDF(secret, "palabra-aead-v1"))`, with AAD = `role byte | counter`. The role byte (`A` app, `W` web) stops a frame being reflected back; the counter stops replays. The plaintext is the envelope `{id, type, version, payload}`. Phase 1 uses `ping` and `ack`; unknown types are ignored.

Both implementations are pinned to the same fixed vectors (`web/test/crypto.test.js`, `PalabraTests/WebLink/LinkCryptoTests.swift`), and the vectors were also checked with an independent Python implementation.

## Honest limits

- **Passive eavesdropper on the same Wi-Fi.** The local hop is plain HTTP. Someone who records one pairing can try codes offline against the proof or the wrapped secret. A 6-digit code falls to that quickly. What stops a stranger is that they must be on this Wi-Fi **and** present during a pairing. If this is too weak, the fix is a password-authenticated key exchange (SPAKE2 or OPAQUE); it changes only `pairingProof` and `wrapSecret`. **Recommended before phase 2 if the Wi-Fi is shared (cafe, dorm).** Longer codes help too.
- **Active attacker on the same Wi-Fi** who races the page can use the five guesses per lockout window, and each guess burns one nonce.
- **Relay.** A public address can be hit by anyone. Rooms are unguessable (128 bits) and capped, but a flood of new rooms still counts against the free tier. Rate limiting per IP is left open (see below).
- The `isLocal` check trusts the TCP source address. It stops other networks, not a device on this one.

## How to try it (needs a device; CI cannot)

1. Deploy the relay: `cd relay && npx wrangler@3 deploy` (your Cloudflare account, free tier). Note the `wss://palabra-relay.<you>.workers.dev` address.
2. Install the IPA from the `experimental` build. Settings > Web Access: switch on, paste the relay address, choose a code, tap Pair a Browser. The phone shows its Wi-Fi address.
3. On the PC (same Wi-Fi), open `web/link-proof.html` **from the disk** (double-click). Fill the three fields, press Pair and ping.
4. The page reports one of: success with milliseconds; `wrong`/`locked`; or `file-blocked-or-unreachable`. Please test Chrome, Edge, Firefox and Safari and record the result below.

### CI status

`experimental` @ `ac0e845`: IPA build, JavaScript job (24 tests) and the Swift suite (1414 cases, 0 failed) are green. This proves the code compiles and the logic is right on both sides. It does **not** prove the real network path (phone listener, `file://` page, relay), which only a device can.

### Result of the `file://` question

_Not yet tested on a device._ Fill in per browser: reached the phone / asked permission / blocked.

## Out of scope in phase 1

No snapshot, no screens, no cache, no outbox, no data access through the capability registry. The only handler is `ping`.
