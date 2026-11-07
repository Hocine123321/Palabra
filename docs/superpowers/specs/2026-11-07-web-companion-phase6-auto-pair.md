# Web companion, phase 6: automatic pairing ("Find my phone")

Status: design. Branch `experimental`.

## What the person gets

1. On the page, **Find my phone** lists Palabra phones that are on the same Wi-Fi and reachable through the relay.
2. Tap one. The phone shows **"Trust this computer?"** with the computer's name and a 4-digit match code.
3. Accept on the phone. The two now trust each other, the trust is saved on both sides, and next time the page connects by itself.
4. The PIN is still used for a **new session** (a browser that has no saved trust). Typing the phone address stays as the manual fallback.

## Why the relay, and not a Wi-Fi scan

A web page cannot scan the local network (no Bonjour, no raw sockets). Probing addresses with `fetch` is slow, blocked as mixed content from an https page, and triggers browser permission prompts. Both ends already reach the relay, so the relay is the meeting point.

## "Same Wi-Fi"

The relay Worker reads the connecting address (`CF-Connecting-IP`) and puts the socket in a **lobby** named `HMAC(server salt, public IP)`. Devices behind the same home router share a public IP, so they share a lobby; a device elsewhere cannot join it. The lobby id is never sent to the client. Limits, said plainly: two networks behind one carrier-grade NAT can share a lobby, and a phone on mobile data is not in the home lobby. This is why the lobby is only **discovery**; trust is decided by the person on the phone.

## Messages (lobby sockets carry JSON text, never secrets)

- phone to lobby: `announce {deviceId, name, pub}` while "Pair a browser" is open, repeated every 5 s, and `gone` when it closes.
- page to lobby: `hello {browserId, name, pub}` to ask who is there; phones answer with `announce`.
- page to phone: `request {to: deviceId, browserId, name, pub}`.
- phone to page: `decision {browserId, accepted, ...}`.

`pub` is an ECDH P-256 public key made for this attempt. The match code is the first 4 digits of SHA-256(phonePub | browserPub), shown on both screens. A fake phone or a man in the middle on the lobby produces a different code, and the person only taps Trust when the codes agree.

## Trust

On Trust, the phone derives a shared key with ECDH and sends the browser a fresh **trust token** (32 random bytes) wrapped under it, together with the real session secret. Saved:
- phone: `{browserId, name, tokenHash, createdAt}` in the Keychain list of trusted browsers (max 8), removable in Settings.
- page: `{deviceId, token, relayUrl}` in IndexedDB, only when "Remember this computer" is on.

Reconnect with trust: the page presents `token` over the encrypted session already established from the secret; the phone checks it against the saved hash. A revoked or unknown token is refused and the page falls back to the PIN.

## Limits and safety

- The lobby accepts at most 16 sockets and 20 frames/s per socket, text only, 2 KB per frame.
- A request can be answered once; the popup times out after 60 s.
- No request can reach the phone unless the phone is in "Pair a browser" or has Web Access on and the app is in front.
- Wrong match code or Decline: nothing is saved on either side.
- The relay logs and stores nothing; lobby frames are public-key material and a display name only.

## Out of scope for this phase

Scanning the local subnet; discovering phones across different networks; sharing trust between browsers.
