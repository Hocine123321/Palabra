# Web companion: Palabra in a browser, linked to the app

Status: **phases 1 to 4 and the Artifacts part of phase 5 are built on the `experimental` branch**, see [phase 1](2026-11-07-web-companion-phase1.md), [phases 2 and 3](2026-11-07-web-companion-phase2-3.md) [phase 4](2026-11-07-web-companion-phase4.md) and [phase 5, Artifacts](2026-11-07-web-companion-phase5.md). Everything beyond them is still vision. It records what was decided in conversation on 2026-11-07 so the
build can start from it later. The open questions were answered the same day (see Decisions); what is still open is at the end.

## Intent

The person wants to use Palabra from a PC. The app on the phone stays the one real copy of the data; a **single HTML file**
opened on the PC is a full web version of the UI that talks to the app. Neither side hosts anything: the app and the HTML file
both dial out to the same small relay and exchange messages through it, on the same Wi-Fi or across the internet. Pairing is
only allowed from the same Wi-Fi.

## Why this shape

- **iOS cannot serve.** An app cannot accept incoming connections in the background, and a phone is not reachable from outside
  its network. It can always make an outgoing connection, so both ends connect out and meet in the middle.
- **A local file avoids hosting and HTTPS.** Service workers and installable web apps need `https://` or `localhost`. A page
  opened from `file://` needs neither. The file is the whole UI; nothing has to be served to load it.
- **The phone stays the source of truth.** No second database, no account, no sync service to run. The Google AI key never
  leaves the phone.

## Goals

1. **One HTML file** (`palabra-web.html`, built from a `web/` folder in this repo) that is the whole UI: same layout, colours,
   typography, spacing and flows as the app (Recortes & Glass, Claude Orange accent, the app's radii), except iOS-only elements.
2. **Link by relay.** The app and the file each open an outgoing WebSocket to the relay and exchange messages. Same-Wi-Fi and
   internet use the same path. A direct local connection may be tried first as a later optimisation; it is not required.
3. **Pairing and encryption.** The person **chooses a pairing code in the app** and **types it into the HTML page**. The link only
   opens when the two match; any other code is refused, and repeated wrong codes lock pairing out for a while (see
   "Same-Wi-Fi pairing"). Pairing only works from the **same Wi-Fi network**, so a stranger on another network cannot pair. Once
   paired, messages are end-to-end encrypted with a session secret, so the relay sees only opaque bytes and holds nothing.
4. **Keep the phone awake while the feature is on.** The app disables the idle timer (`isIdleTimerDisabled`) while web access
   is switched on, and shows a clear "Web access is on" state. The setting says it uses more battery.
5. **Works with the phone offline.** The first time the file connects it pulls a snapshot of the app's data into the browser's
   storage (IndexedDB). After that the UI opens and navigates without the phone. It shows "last synced" and what is waiting.
6. **Outbox.** Actions that need the app are queued in the browser and sent in order when the app is reachable. Each carries an
   id and the version of the record it was based on, and is retried until the app confirms it.
7. **Settings control in the app.** One switch, a pairing screen (code, QR, paired devices, revoke), and a status line.

## Behaviour rules

- **The phone wins conflicts.** If a queued action was based on a stale version, the app rejects it. Rejected actions go to a
  "needs review" list in the web UI with the reason; the person decides to retry, edit or drop.
- **Not everything is queued.** Actions that cost something or cannot be undone (AI calls, deletes, anything that spends quota)
  wait for a live connection and are not replayed silently from a stale queue.
- **AI calls run on the phone.** The web UI asks the app to make them. API keys, the backup key and model settings never
  cross the link.
- **Reads come from the cache when the app is away,** and are refreshed from the app when it is back.
- **Foreground only.** iOS suspends sockets when the app is backgrounded or the phone locks, so the link only exists while the
  app is open. This is stated in the feature's own settings text, not hidden.

## Same-Wi-Fi pairing

The person's rule: pairing must only work when the app and the HTML file are on the same Wi-Fi, so nobody on another network
can pair. A relay on the internet cannot see anyone's Wi-Fi, so the rule is enforced **at pairing time over a direct local
connection**, and the relay is used only afterwards:

1. The app opens a small local listener (Network.framework, `Bonjour` service) only while the **Pair a browser** screen is open.
2. The HTML file, opened on the PC on the same network, finds it and connects to the phone's local address. This direct hop is
   the proof of "same network": a device on another Wi-Fi cannot reach a private address.
3. The person types the code (chosen in the app) into the page, and the page sends it. The app checks it matches. If so, the app
   returns a **session secret** over that local hop, and both store it. The code alone is not enough, and the secret never
   touches the relay in the clear. **A wrong code is refused. After 5 wrong tries the app refuses all attempts for a lockout
   that grows with each repeat (30 seconds, then 2 minutes, then 10 minutes, capped at 1 hour), and says so on both screens.**
   The counter lives in the app, so reloading the page does not reset it.
4. From then on the two connect out to the relay (Wi-Fi or internet) and encrypt with the session secret. The relay never sees
   the code or the secret.
5. Pairing can be redone or revoked from the app at any time; revoking invalidates the secret.

Consequences, stated honestly: the code is short enough to type, so it is not strong on its own. What protects the link is the
**same-network check plus the lockout**: a stranger must be on this Wi-Fi, and gets only a few guesses per lockout window.
The code should be at least 6 digits, shown in the app only while pairing is open, and changed each time pairing is opened.
Because browsers may ask for local-network permission, or block `file://` pages from reaching a LAN address, pairing may need
a one-time browser prompt, and the build must prototype this first (phase 1). If a browser refuses it outright, there is no
automatic fallback: the page says so and points to a browser that allows it.

## Cache scope

- **The 2D pages UI is cached in full:** Library, Study, Artifacts, Chat history (recent only, see below), Settings views. The
  person opens the file once while the app is online and the snapshot is stored.
- **Books content is cached on demand, in order of visit:** a book's content is stored only after the person navigates to the
  Books page and opens it. Nothing from Books is pre-fetched. Books never opened while online are unavailable offline.
- **Chat history: only the most recent conversation is cached.** Older conversations load only while the app is reachable.
- Cached data shows "last synced"; a queued action shows as waiting.

## Architecture

```
web/                       source of the single HTML file (UI, state, outbox, crypto, relay client)
relay/                     the relay: forwards messages between two paired ends, stores nothing
Palabra/Features/WebLink/  the app side: pairing, relay client, message handlers, keep-awake, settings screen
Palabra/App/CapabilityProviders.swift   reused as the data door: the web UI reads and writes through the same capabilities
```

- **Data access goes through the capability registry,** the same door Artifacts use (`library.words`, `words.add`, ...). New
  web needs become new capabilities, so the grant and dry-run rules stay in one place.
- **Message envelope:** `{id, type, version, payload}` encrypted as a whole; `type` is one of `snapshot`, `read`, `write`,
  `ai`, `ack`, `reject`, `ping`. Unknown types are ignored, so old files and new apps keep working.
- **Snapshot** carries the screens' data (words, sections, tags, stats, study state, artifacts) with a version per record.
- **Relay:** a tiny WebSocket service keyed by a room id derived from the **session secret** (not the pairing code, which the relay must never see). It cannot read messages and keeps no
  history. It is the only piece that has to be hosted; a free tier is enough.
- **Build:** `web/` is bundled into one file by a script, with no external URLs (fonts and icons inlined), so it also runs offline.

## Phases (CI green and verified after each)

1. **Link proof:** the local pairing hop (same-network check), the relay, encryption, and an encrypted ping between the app and a
   bare HTML page. No UI yet. Settles whether browsers allow the `file://` to local-address hop.
2. **Read-only web:** snapshot over the link, the design tokens, navigation, and the first screens (Library, Study).
3. **Offline:** persistent cache in the browser, "last synced", usable with the app away.
4. **Outbox:** queued writes, ordering, retries, rejection and the "needs review" list, AI calls over the link.
5. **More screens:** Artifacts first (they already run in a sandboxed web view), then Chat (most recent conversation cached), then
   the Books pages with on-visit caching. The 3D desk stays out of scope.
6. **Optional:** direct same-Wi-Fi connection before the relay; push relay out of the free tier if it is ever needed.

## Non-goals

- No account, login or cloud copy of the person's data; the relay is a pipe, not a store.
- No hosting of the UI (no website, no certificate, no service worker).
- No change to existing persisted names (bundle id, SwiftData entities, UserDefaults keys); the web feature only adds new ones.
- No background syncing while the app is suspended; iOS does not allow it.
- No pixel-identical copy of iOS-only things (haptics, system sheets, glass materials, the SceneKit desk). They get web
  equivalents or simplified versions; the 3D desk is not rebuilt for the web.

## Anti-goals

- A relay that can read the person's words or spend their AI quota.
- Silent replay of a stale outbox: no queued delete or AI call fires without a live, confirmed connection.
- A second set of business rules in JavaScript. The app decides; the web UI displays and asks.
- A feature that quietly keeps the phone awake. The keep-awake behaviour is on only while the switch is on, and visible.

## Constraints

- The idle-timer override only works in the foreground and only while the feature is on; it is released when the switch is off
  or the app leaves the screen.
- Chrome and Edge may show a one-time "local network" prompt if a direct connection is added later; Safari is stricter.
- IndexedDB quota varies by browser; the snapshot must stay small enough to be stored (trim audio and large artifacts, load
  them on demand).
- The pairing code is the only secret. Losing it means re-pairing; revoking a device invalidates its code.

## Decisions (2026-11-07)

- **Relay host:** a Cloudflare Worker with a Durable Object relaying WebSocket frames, free tier, owned by the person's own
  Cloudflare account. Chosen because it needs no server, stores nothing, and the free tier covers one person's traffic.
- **Pairing UI:** the person chooses the code in the app and types it into the HTML page; a wrong code is refused and repeated
  failures lock out for a growing time. No QR, and no code stored in the HTML file (see "Same-Wi-Fi pairing").
- **Books:** only the 2D pages UI is part of the web version; Books content is cached by visit order (see "Cache scope"). The
  3D desk is not rebuilt in WebGL for the first versions.
- **Chat:** only the most recent conversation is cached for offline use; older ones need a connection.

## Open questions

- Whether browsers let a `file://` page reach the phone's local address for the pairing hop (Chrome and Edge ask for
  local-network permission; Safari is stricter). Phase 1 settles this.
- How the HTML file reaches the person's PC. It holds no per-device secret any more, so one built file works for everyone and
  can simply be downloaded from the repo's releases or exported from the app. Which of the two is open.
- What the relay does about abuse (rate limits per room), since it is a public address, even though it stores nothing.
