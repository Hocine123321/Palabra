# Web companion, phases 2 and 3: read-only web and offline copy

Status: built on `experimental`. Builds on [phase 1](2026-11-07-web-companion-phase1.md); the vision is in the
[main spec](2026-11-07-web-companion-design.md). Nothing here has run on a real phone yet.

## What the person gets

Open `palabra-web.html` on the PC, pair once, and see **Library** (search, tag filter, sections, the app's tile colours) and
**Study** (decks with due and new counts, words to review, words added per day). With "Remember this computer" ticked, the page
opens later straight onto the saved copy, says the phone is away and when it last synced, and reconnects by itself when the
phone is back. English and Arabic (right to left), following the browser language.

## Messages added to protocol v1

Every message is still `{id, type, version, payload}`, encrypted as a whole. Unknown types are ignored.

| Type | From | Payload | Reply |
|---|---|---|---|
| `read` | page | `{capability, args}` | `ack {result}` or `reject {reason}` |
| `snapshot` | page | none | `ack {snapshot, takenAt}` or `reject {reason}` |
| `chunk` | phone | `{index, total, data}` (base64 of the whole reply message) | the page reassembles by `id` |

Reject reasons: `forbidden`, `bad-request`, `bad-args`, `rate-limited`, `failed`. A page that waits 15 s for an answer reports
"the phone did not answer".

**Read-only is enforced on the phone, in two places.** `WebLinkDispatcher` allows only `library.words`, `library.word`,
`study.decks`, `review.list`, `stats.wordsPerDay`, `stats.wordsPerWeek`, and then also checks that the registry itself
classifies the capability as a read. `words.add`, `ai.generate`, `storage.*` and every write are refused and never run. API keys
are not reachable through any allowed capability. The snapshot is all or nothing: if one read fails, the page gets a `reject`,
never a half-filled snapshot that looks complete.

**Chunking.** The relay drops frames over 256 KB. Replies over 120 KB are cut into pieces; Swift and JavaScript tests both
check that every sealed piece fits, that pieces can arrive in any order, and that a missing piece leaves the request to time out
instead of showing a truncated library.

## The page

- `web/src/ui/model.js`: pure view-models (search ignores case and accents; the tile colour is a port of the app's FNV-1a
  `WordKey.tintIndex`, pinned by values computed independently, accents included).
- `web/src/ui/render.js`: HTML as strings. Every piece of phone data is escaped; a test feeds `<img onerror>` through every screen.
- `web/src/ui/tokens.css`: the app's colours, radii and spacing. `tokens.test.js` reads `Theme.swift` and **fails if they drift**.
- `web/src/ui/strings.js`: English keys and Arabic values. Tests fail if any text the code uses, any marked text in the page, or
  any link error message lacks Arabic.
- `web/scripts/build.js`: bundles everything into one file with no outside URLs (about 40 KB). A test runs the bundle and a
  fake-DOM test drives it: pairing, offline start, forget.

## Offline copy (phase 3)

- `web/src/cache.js`: a small key-value interface over IndexedDB (and an in-memory one for tests). Stored: the last snapshot
  and, if the person agreed, the pairing. A stored shape from another schema version is ignored, not misread. Storage failures
  (quota, private mode) never throw into the page.
- `web/src/sync.js`: the state machine. Shows the saved copy first, then tries the phone: `connecting`, `linked`, `away`
  (has a saved copy), `empty` (none), `error` (needs the person). Retries after 2 s, 5 s, 15 s, then every 30 s, one at a time.
  A reply that is damaged is never saved over a good copy. After 4 silent attempts in a row the page suggests that the
  browser may have been removed in the app.

### Privacy decisions (please review)

1. **"Remember this computer" is off by default, and nothing is written to the browser unless it is ticked.** A test pairs
   through the real form with it off and checks the browser kept nothing.
2. When on, the browser keeps **your words and the link key**. Anyone who can use that browser profile can read the words and
   open the link, until the phone removes the pairing. The page says so beside the checkbox (English and Arabic).
3. **"Forget this computer"** deletes the key and every saved word and returns to pairing.
4. The key is stored as plain bytes in IndexedDB. Encrypting it needs a second secret, which would be another thing to type;
   that was not done. If this matters, the alternative is to never remember the key (words only), and pair each time.

## Known limits

- **Revoking on the phone cannot tell the page.** The relay only forwards bytes, so a revoked page sees the same silence as an
  absent phone. The hint after 4 attempts is the honest substitute. A real signal would need the relay to know about revocation.
- The page is **read-only**: no outbox yet (phase 4). "Needs review" lists the phone's flagged words but cannot change them.
- Only Library and Study exist. Word detail, Artifacts, Chat and Books are phases 4 and 5.
- Chrome and Edge prompt for local network access; Safari is stricter. Still unverified on a device (open question 1 of the
  main spec, settled by phase 1's test page).
- Nothing in Swift has been compiled for phases 2 and 3 yet; CI will say.
