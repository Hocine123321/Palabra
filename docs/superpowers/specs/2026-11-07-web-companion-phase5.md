# Web companion, phase 5 (part 1): Artifacts

Status: built on `experimental`. Artifacts, Chat and Books are built (see "Chat and Books" at the end). Builds on [phase 4](2026-11-07-web-companion-phase4.md).

## What the person gets

A third tab, **Artifacts**. It lists the pages you made in Palabra; tapping one opens it on the PC (headings, text, lists, tables,
charts, stats, checklists, roadmaps, sections, columns). Apps (the interactive ones) appear in the list marked **Opens on your
phone**.

## Decision to review: apps do not run on the web yet

An `app` artifact is generated HTML with script and a bridge (`window.palabra`) to the phone. In the app it is confined by a WebKit
content rule plus a CSP, and `ArtifactSandbox` calls those values "the security boundary". A browser page cannot copy that
boundary by itself, and the page that would host the artifact also holds the link key. Running generated script there could read
the person's data or send changes. So apps are listed and never sent: the phone answers `not-found` even if the page asks for one
by id (tested).

To run apps safely later it needs, at least: a sandboxed iframe with no `allow-same-origin`, a CSP on its `srcdoc`, and a
message bridge that only forwards the capabilities that artifact was granted, through the same allow-list as the page. That is
a design of its own and deserves its own review, so it is left out here.

## Messages added (all read-only)

| Type | Payload | Reply |
|---|---|---|
| `artifacts` | none | `ack {result: [{id, title, kind, viewable, runnable, updatedAt}]}`, newest first, at most 200, **never a payload** |
| `artifact` | `{id}` | `ack {result: {id, title, blocks}}` for a page; `reject not-found` for an app, an unknown id or an undecodable page |

**The phone does the work, the page only draws.** `WebArtifactReader` decodes the page and resolves tables and charts with the app's
own `SpecBindLoader`, so there is no second copy of the binding rules in JavaScript. Binds are limited to the reads the web page may
already make (`readAllowList`); a bind to anything else (`storage.get`, a write) shows an inline note and runs nothing (tested).
Checklist and roadmap ticks are sent as they are on the phone.

**The page does not trust the phone's limits.** It re-caps nesting at 4 levels and 60 blocks, escapes every string, draws nothing
for an unknown block type, and survives junk where lists are expected (tested, including an `<img onerror>` in every field).

## Limits

- Read-only: ticking a checklist on the web is not possible yet. It would be a new write (and a new line on the write allow-list), so
  it is a deliberate next step, not an accident.
- Artifacts are fetched live and are **not** saved in the browser, so the tab needs the phone connected. When it is away the tab says
  so. (Offline artifacts would need the cache to hold them; the cache size and what to keep are for you to decide.)
- No version history, restore or delete from the web.
- Nothing in Swift for phase 5 has been compiled or run yet.

## Still to build in phase 5

Chat (most recent conversation, cached) and Books (pages cached on visit).


## Chat and Books (phase 5, part 2)

Two more tabs, read-only, over the same encrypted link. Nothing from either is stored in the browser, so "Remember this computer" is unchanged.

**Phone** (`WebChatBooksReader`, injected closures returning plain values, like `WebArtifactReader`). New request types: `chat`, `books`, `lesson {book, lesson}`.
- **Chat:** the most recent conversation, newest 60 turns, each cut to 4,000 characters. Never sent: photos, thumbnails, the arguments or results of tool calls. A turn says only how many actions it ran and whether it failed.
- **Books:** the catalogue (books, chapters, lesson titles). A lesson is sent as text pages. Headings, paragraphs, lists, key points, quotes and definitions become text; layout-heavy blocks (timelines, comparisons, diagrams, images) become a note, "This part is best read on the phone", not a guess.
- Unknown lesson ids answer `not-found`; malformed requests `bad-request`; with no reader wired the page sees "no chat / no books", not an error.

**Page** (`ui/chatbooks.js`): every string escaped, counts capped again, unknown block kinds draw nothing. Chat is read-only ("To reply, open it on your phone"). All new text has Arabic.

## Fix: "Connecting..." forever (found on a real phone)

`openLink` waited for the socket to open with no limit and only listened for `error`, so a refused, closed-before-open or silent socket (wrong relay address, relay not deployed, `https://` typed instead of `wss://`) never settled. Now:
- Opening the relay has a 10 s limit; a close before open is a failure; close code 4001 says another browser is linked.
- The relay address is tidied (`https://` becomes `wss://`, trailing slashes dropped) and obvious mistakes are explained.
- The status shows its step ("Reaching the relay...", then "Reached the relay. Waiting for the phone..."). At most about 25 s passes before a reason appears.
- The phone never drops a request silently: a reply that cannot be built or sealed is answered with a `reject`.


## Fix: "waiting for the browser" on the phone, "waiting for the phone" on the page

Both ends said the relay was fine, yet never met. Two causes, both fixed:

1. **The relay address was typed in two places.** The phone used the one in its Settings, the page the one typed on the pairing card. Any difference (another Worker, an old deploy, a typo) put the two ends in different relays, each reporting a healthy connection. Now the phone seals its own relay address together with the session secret (`secret(32) | address`, inside the same encrypted box, so the network sees neither). The page joins that address and ignores a typed one; the field is optional and only used with an older app that sends none. The phone stores only the 32-byte secret.
2. **The phone never reconnected.** When its socket failed or closed (Wi-Fi blip, iOS closing an idle socket), it showed "waiting for the browser" with a dead connection until the app was reopened. It now retries after 1, 2, 4, 8, then every 15 seconds while the app is in front and Web Access is on, and stops only for "another browser is already linked". Leaving the app or switching relay does not trigger a retry.

The relay still refuses a third end on purpose: evicting the oldest would let anyone who learns a room id push the real phone out.

Pairings made with the old app have no relay address inside, so the page falls back to the typed one. Install the new build on the phone and pair again for the automatic behaviour.

## Removing one computer no longer signs out the others

A computer you chose to trust keeps a token. After joining, its page sends `hello` with that token. The phone keeps only a hash of each token (`TrustedBrowsers`) and checks it with `TrustGate`:

- a browser paired with the six digit code sends no hello and works exactly as before;
- a trusted computer whose token is on the list is answered;
- a computer that was removed (or presents an unreadable token) gets `revoked` on its hello and on every later request, even while connected, and its page shows "This computer is no longer trusted by the phone" and stops retrying.

The shared link secret is not changed, so the other trusted computers keep working. Limitation: a computer that holds the secret but never sends a hello is treated as a code-paired browser. A removed computer that deliberately skips the hello is therefore not cut off. Closing that needs a per-computer key instead of one shared secret, which is a larger change.
