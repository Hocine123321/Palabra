# Mirroring, plan 3b: the other collections, on the phone and in the page

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the spec lists for reading without the phone is pushed and shown in the page: word details, Study (decks, due counts, stats), Need Review, Artifact pages, the latest Chat conversation, and the Books lessons (2D reading).

**Architecture:** Each collection is a new record kind. The App layer (`Palabra/App/AppEnvironment+Mirror*.swift`, the only place that sees `Deck`, `Card`, `ReviewNeed`, `Artifact`, `ChatConversation`, `Lesson`) turns them into `MirrorRecord`s of plain JSON; `Features/Mirroring` only pushes them. `MirrorService.sync` takes the set of kinds that were **successfully built** this time, so a collection that could not be read is left alone, never tombstoned. The page gets hash routes, a navigation bar and one render function per kind; every phone string is a text node.

**Tech Stack:** Swift/XCTest + `MockURLProtocol` (iOS 17); web: plain ES modules, the existing `h`/`mount` DOM builder, IndexedDB, Node test runner with `fake-indexeddb`; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-07-mirroring-design.md` (Goals 1; Syncing data; The web app; Phase 3). **Builds on:** plan 3a (manifest, freshness badge, installable app) and plans 1-2. Plan 3c (rotation) is independent of this one.

## Global Constraints

- **Record kinds and ids** (`recordID` is the phone's own id, the item id is derived as before):
  - `word` (exists), plus no change.
  - `deck` (recordID = deck UUID): `{id, name, kind: "vocabulary"|"user", createdAt, counts: {total, due, new}, countsAt}`; `countsAt` = ISO-8601 time the counts were computed.
  - `card` (recordID = card UUID), **user decks only** (the vocabulary deck is derived from the words): `{id, deckId, front, back, due, reps, lapses, phase, createdAt}`.
  - `stats` (recordID `"stats"`): `{reviewedToday, streak, lastSevenDays: [Int x7], asOf}`.
  - `review` (recordID = need UUID), open needs only: `{id, wordId, headword, translation, score, note, flagCount, updatedAt}`.
  - `artifact` (recordID = artifact UUID): `{id, title, kind: "spec"|"app", version, updatedAt, blocks}`; for `spec`, `blocks` is the spec's block list with every table and chart **resolved by the phone** (bound ones replaced by inline rows/series, a bind that fails becomes `{"type":"error","message":"Couldn't load data"}`); for `app`, `blocks` is `null` (apps are listed, never shipped).
  - `chat` (recordID `"latest"`): the most recently updated conversation `{id, title, wordId, updatedAt, turns: [{role, text, createdAt, status}]}`; no thumbnails, no actions, no error text.
  - `lesson` (recordID = lesson id): `{id, version, title, summary, bookId, bookTitle, chapterId, chapterTitle, language, pageIds: [String], terms, notes}` and `lessonPage` (recordID `"<lessonId>/<pageId>"`): `{lessonId, id, number, title, dateLabel, blocks}`, `blocks` in the same JSON shape `docs/features/books.md` documents for lesson files. One item per page keeps every item far below the 262,144-character cap.
- Never mirrored: pronunciation audio, images' bytes (an `image` block ships its `alt` and `caption` only), API keys, older chats, Lesson Studio drafts.
- `MirrorService.sync(records:kinds:force:)`: `kinds` is the set of kinds built successfully this sync (for a failed build the kind is omitted, so nothing of that kind is tombstoned).
- A Worker answer `409 mirror_full` shows as the new `MirrorSyncError.full`: "The Worker is full. Remove old data on the Worker or pair a new one." (Arabic key added.)
- Page routes (hash): `#/words`, `#/words/<itemId>`, `#/study`, `#/review`, `#/artifacts`, `#/artifacts/<itemId>`, `#/chat`, `#/books`, `#/books/<lessonItemId>`; anything else goes to `#/words`. Direction of a book follows its `language`; the app chrome follows the browser language.
- The page contains no business rules: due counts, streak and scores are shown as the phone sent them, labelled with their `asOf`/`countsAt` time.
- Existing rules hold: `Features/Mirroring` imports no `Word/Deck/Card/ReviewNeed/Artifact/Chat/Lesson` types; strict CSP, no `innerHTML`, no inline style; every new UI string has an Arabic key (`web/src/strings.js`, `ar.lproj` + `LocalizationTests`); tokens test keeps the colours equal to `Theme.swift`; no direct `withAnimation`/`.animation`.
- After any Swift change say plainly: compiled by eye only until a real CI run.

## Review Focus

- One collection cannot be read (a SwiftData fetch fails, an artifact's bind throws, `chat` has no conversation): the other kinds still sync and nothing of the failed kind is deleted from the mirror (Task 1 and 3 tests).
- Hostile or odd content in every collection (`<img src=x onerror=...>` in a deck name, card side, review note, artifact title and table cell, chat text, lesson title and block text; Arabic and RTL text; a 3,000-character paragraph; emoji): rendered only as text, on every screen (Tasks 5-7 tests feed one markup string through all screens).
- Unknown or malformed payload from the phone (a block type the page does not know, `blocks` not an array, a missing `turns`, a number where text is expected): the screen shows what it can, the rest as plain text, and never throws (Tasks 5-7).
- The mirror gets big (hundreds of lesson pages, thousands of cards): batching keeps every PUT under 200 items / 900,000 characters, a `409 mirror_full` is reported, and `list`/`pull` paging still completes (Task 4 + Task 6).
- A word, deck, artifact or lesson is deleted on the phone: its item is tombstoned and the page drops it, and a route to a vanished item shows "That item is gone" not a blank screen (Tasks 2, 3, 5-7).

---

## File structure

```
Palabra/App/AppEnvironment+Mirror.swift (sync entry, kinds)   AppEnvironment+MirrorStudy.swift  AppEnvironment+MirrorContent.swift  AppEnvironment+MirrorBooks.swift
Palabra/Features/Mirroring/Sync/MirrorService.swift  (kinds parameter, .full)
PalabraTests/Mirroring/MirrorStudyRecordsTests.swift  MirrorContentRecordsTests.swift  MirrorBooksRecordsTests.swift  MirrorServiceTests.swift
web/src/router.js  nav.js  render/word.js study.js review.js artifacts.js chat.js books.js blocks.js   (screens)  main.js  view.js  strings.js  app.css
web/test/router.test.js  screens.test.js  blocks.test.js
docs/features/mirroring.md ("What is mirrored")
```

### Task 1: Collections plumbing and the study records

**Files:**
- Create: `Palabra/App/AppEnvironment+MirrorStudy.swift`, `PalabraTests/Mirroring/MirrorStudyRecordsTests.swift`
- Modify: `Palabra/App/AppEnvironment+Mirror.swift`, `Palabra/Features/Mirroring/Sync/MirrorService.swift`, `PalabraTests/Mirroring/MirrorServiceTests.swift`, `PalabraTests/Mirroring/MirrorWordRecordsTests.swift`

**Interfaces:**
- Produces:
  - `struct MirrorCollection { let kind: String; let records: [MirrorRecord] }` in `Features/Mirroring/Sync/MirrorRecord.swift`
  - `MirrorService.sync(collections: [MirrorCollection], force: Bool = false) async` (replaces `sync(records:force:)`; the pusher is called with `kinds` = the collections' kinds, records = their concatenation; the manifest from plan 3a is unchanged)
  - `AppEnvironment.mirrorCollections() -> [MirrorCollection]` (words, then each later collection that built without error; a builder that throws or returns a partial read is omitted)
  - `AppEnvironment.mirrorStudyCollections() -> [MirrorCollection]` for `deck`, `card`, `stats`, `review`
  - `MirrorSyncError.full` (status 409 with code `mirror_full`)

- [ ] **Step 1: Write failing tests.** `MirrorServiceTests`: update every `sync(records:)` call to `sync(collections: [MirrorCollection(kind: "word", records: ...)])`; add `testAKindMissingFromTheCollectionsIsNeverTombstoned` (sync with `word` + `deck` records, then sync with only `word` -> no tombstone request for the deck item; sync with `deck` present but empty -> a tombstone for it), `testMirrorFullIsReported` (PUT answers 409 `{"error":"mirror_full"}` -> `lastError == .full`). `MirrorStudyRecordsTests` (in-memory repositories as the existing `MirrorWordRecordsTests` does): a vocabulary deck and a user deck with 2 cards -> two `deck` records with the exact counts, only the 2 user cards as `card` records (the vocabulary deck's cards are absent), the `stats` record has 7 numbers in `lastSevenDays`, an open need becomes a `review` record and a cleared one does not, payload keys are exactly those in Global Constraints, no `sourceWordID` or SRS ease leaks, the markup string `"<img src=x onerror=1>"` survives unchanged in a deck name.
- [ ] **Step 2: Run `bash scripts/check-conventions.sh`; implement** `MirrorCollection`, the new `sync`, `mirrorCollections()` (existing word records become the first collection), the study collections using `cards.decks()`, `cards.counts(now:)`, `cards.cards(inDeck:)`, `cards.reviewStats(now:)` and `review.openNeeds()` (ISO-8601 dates as in the word records), `MirrorSyncError.full` plus its Arabic string and `LocalizationTests` entry, and change `AppEnvironment.mirrorSyncIfEnabled` to pass `mirrorCollections()`.
- [ ] **Step 3: Commit** `feat(mirror): collections plumbing, decks, cards, stats and review records`.

### Task 2: Artifact and chat records

**Files:**
- Create: `Palabra/App/AppEnvironment+MirrorContent.swift`, `PalabraTests/Mirroring/MirrorContentRecordsTests.swift`
- Modify: `Palabra/App/AppEnvironment+Mirror.swift` (add the collections to `mirrorCollections()`)

**Interfaces:**
- Consumes: `artifacts.artifacts()`, `artifacts.versions(artifactID:)`, the spec decoder and `SpecBindLoader` (`table`, `chart` async resolvers), `chat.conversations()`.
- Produces: `func mirrorContentCollections() async -> [MirrorCollection]` for `artifact` and `chat` (async because bound blocks resolve through the registry; `mirrorCollections()` becomes `async` and its callers `await` it).

- [ ] **Step 1: Write failing tests:** a spec artifact with a table bound to `library.words` and a chart with inline data comes out with the table rows inlined and the chart unchanged; a bind that fails yields the error block and the rest of the artifact is intact; an `app` artifact gives `blocks == nil` and never includes its HTML payload; a spec whose payload no longer decodes is left out of the `artifact` collection while the others stay (the collection still counts as built, so that one artifact is tombstoned if it was pushed before; assert this deliberately); only the most recently updated conversation is mirrored, with turn texts and roles, no `thumbnail`/`actions`/`errorText`; no conversations -> the `chat` collection is present and empty (tombstones an old `latest`).
- [ ] **Step 2: Implement** with the existing decoders only (no second parser); resolve bound blocks with a session created for mirroring that is granted only `.read` capabilities.
- [ ] **Step 3: Commit** `feat(mirror): artifact pages and the latest chat as records`.

### Task 3: Books lessons as records

**Files:**
- Create: `Palabra/App/AppEnvironment+MirrorBooks.swift`, `PalabraTests/Mirroring/MirrorBooksRecordsTests.swift`
- Modify: `Palabra/App/AppEnvironment+Mirror.swift`

**Interfaces:**
- Consumes: `books.library` (books, chapters, lessons with pages), `books.lesson(id:)` for terms.
- Produces: `func mirrorBooksCollections() -> [MirrorCollection]` for `lesson` and `lessonPage` (Global Constraints shapes).

- [ ] **Step 1: Write failing tests** with a small in-memory `BookShelf` (the existing `BookShelf.inMemory()` plus a temporary `LessonStore`): 2 lessons, 3 pages -> 2 `lesson` and 3 `lessonPage` records with numbers 1..3 in book order; `pageIds` match; an `image` block carries only `alt` and `caption`; a lesson with an `unsupported` block keeps its `type` name; a 3,000-character paragraph and Arabic text survive byte for byte; deleting a lesson removes its records from the next build (so the pusher tombstones them); every item stays under 262,144 characters once sealed (assert on `Base64URL.encode(sealed).count` for the largest bundled lesson page, loading the real bundle JSON the way `BookShelf` does).
- [ ] **Step 2: Implement** by encoding the existing `Block` Codable values (no hand-written block serializer) and stripping image data. **Step 3: Commit** `feat(mirror): books lessons as records`.

### Task 4: Push all collections, sizes and limits

**Files:**
- Modify: `Palabra/App/AppEnvironment+Mirror.swift`, `PalabraTests/Mirroring/MirrorServiceTests.swift`, `MirrorPusherTests.swift`, `docs/features/mirroring.md`

- [ ] **Step 1: Write failing tests:** a service sync with all collections (words, decks, cards, stats, review, artifact, chat, lesson, lessonPage) sends only batches of at most 200 items and 900,000 characters (inspect the PUT bodies; use 450 small records to force three batches); the manifest `counts` has one entry per kind present; a second identical sync sends nothing but, after the heartbeat, one manifest; changing one deck name sends exactly one item plus a manifest.
- [ ] **Step 2: Implement** whatever the tests show missing (expected: nothing beyond Tasks 1-3 except wiring `mirrorCollections()` into `mirrorSyncIfEnabled`). **Step 3:** update "What is mirrored" in `docs/features/mirroring.md` with the kinds from Global Constraints and the "Never mirrored" list. **Step 4: Commit** `feat(mirror): sync every collection`; push and read the Build and Mirror workflows; fix compile errors or failing Swift tests RED -> GREEN.

### Task 5: Page shell, routes, word details

**Files:**
- Create: `web/src/router.js`, `web/src/nav.js`, `web/src/render/word.js`, `web/src/render/blocks.js`, `web/test/router.test.js`, `web/test/screens.test.js`
- Modify: `web/src/main.js`, `web/src/view.js`, `web/src/strings.js`, `web/src/app.css`

**Interfaces:**
- Produces: `parseRoute(hash: string): {name: "words"|"word"|"study"|"review"|"artifacts"|"artifact"|"chat"|"books"|"book", id: string | null}`; `navBar({route, lang, counts}, tr): Node` (links `#/words` ... with the current one marked `aria-current="page"`); `wordDetail({word, lang}, tr)` showing spanish, translation, part of speech, category, tags and the lesson `content` (3 example paragraphs, meanings, usage and register, forms, similar words: render whichever of these keys the phone sent, unknown keys as plain text lists, never as markup); `blockNodes(blocks: any, tr): Node[]` shared by artifacts and books (the block shapes from Global Constraints; unknown type -> its text or `type` name as a paragraph).
- `main.js` renders the bar plus the routed screen; the words screen from plan 2 becomes the `#/words` route; the freshness line from plan 3a stays above every screen.

- [ ] **Step 1: Write failing tests.** `router.test.js`: each route string parses; `""`, `"#/nope"`, `"#/words/"` -> words; ids are kept verbatim. `screens.test.js` (shared `MARKUP = "<img src=x onerror=alert(1)>"`): `wordDetail` with MARKUP in every text field renders text nodes only (walk the tree: no `img` element anywhere); a word with `content` missing, `null`, a string, and an array of numbers does not throw; `navBar` marks exactly one link current and has Arabic labels in `ar`; `blockNodes` handles each known block type, an unknown type, `blocks` of `null`, a string, and 3,000 characters of text without throwing.
- [ ] **Step 2: Implement; Step 3: `npm --prefix web test`; build; commit** `feat(web): routes, navigation and word details`.

### Task 6: Study and Need Review screens

**Files:**
- Create: `web/src/render/study.js`, `web/src/render/review.js`
- Modify: `web/src/main.js`, `web/src/strings.js`, `web/src/app.css`, `web/test/screens.test.js`

**Interfaces:**
- Produces: `studyScreen({decks, cards, stats, lang}, tr)` (deck list with `counts` and "as of <time>", the deck's user cards behind a deck link `#/study/<deckItemId>` is **not** in this plan: cards show inline in a collapsible `details` element per user deck; stats tile row: reviewed today, streak, bar row for the last 7 days with text values); `reviewScreen({needs, words, lang}, tr)` (each need with headword, translation, note, flag count; links to `#/words/<itemId>` when the word exists in the local copy).

- [ ] **Step 1: Write failing tests:** deck with MARKUP name and a card with MARKUP front/back -> text only; counts show the phone's numbers and the `countsAt` time, an unparseable `countsAt` shows no time; `lastSevenDays` of the wrong length or with strings renders 7 zero bars (never throws); empty collections show "Nothing here yet" (Arabic key); a review need whose word is gone renders without a link; sort order: decks by name, needs by `updatedAt` descending.
- [ ] **Step 2: Implement; Step 3: test, build, commit** `feat(web): Study and Need Review screens`.

### Task 7: Artifacts, Chat and Books screens

**Files:**
- Create: `web/src/render/artifacts.js`, `web/src/render/chat.js`, `web/src/render/books.js`
- Modify: `web/src/main.js`, `web/src/strings.js`, `web/src/app.css`, `web/test/screens.test.js`, `web/test/blocks.test.js`

**Interfaces:**
- Produces: `artifactList({artifacts, lang}, tr)` (spec first, `app` ones listed with "Open this on your phone"), `artifactScreen({artifact, lang}, tr)` (spec blocks: heading, text, list, table, chart as an inline SVG of rects with `<title>` text values (no inline style; bar heights via attributes), stats, checklist and roadmap read-only, columns, section, error); `chatScreen({chat, lang}, tr)` (turns in order, role label, text with line breaks kept via separate text nodes); `booksScreen({lessons, lang}, tr)` (grouped by book and chapter, then `bookReader({lesson, pages, lang}, tr)` with the page `blocks` through `blockNodes`, `dir` from the lesson's `language`, page order by `number`, a table of contents of page titles).

- [ ] **Step 1: Write failing tests:** MARKUP in an artifact title, table cell, chart label, checklist item, chat text and lesson/page titles and blocks -> text only; each spec block type renders; `chart` with unequal label and value counts, empty series, `NaN` values renders without throwing; an artifact whose `blocks` is not an array shows "This page can't be shown here"; chat with `turns` missing shows the empty state; a lesson with 0 pages renders its title and an empty-state line; an Arabic lesson sets `dir="rtl"` on the reader root and an English one `ltr` regardless of the browser language; a route to a vanished id shows "That item is gone".
- [ ] **Step 2: Implement; Step 3: test, build, commit** `feat(web): Artifacts, Chat and Books screens`.

### Task 8: Phase check, CI, report

**Files:**
- Modify: `web/scripts/e2e-local.mjs` (from plan 3a), `docs/features/mirroring.md`

- [ ] **Step 1: Extend `e2e-local.mjs`:** a JS phone pushes one record of each kind (including an Arabic lesson with 2 pages and a spec artifact with a table and a chart) plus a correct manifest; with real Chromium click through every nav link and each detail route, assert no console error or CSP violation, assert MARKUP is text on every screen, take screenshots at DPR 2 (light, dark, narrow) of Words, Word detail, Study, Review, Artifact, Chat, Books reader (Arabic, RTL).
- [ ] **Step 2: Run** `npm --prefix web test`, `npm --prefix worker test`, `python3 web/scripts/verify-vectors.py`, `bash scripts/check-conventions.sh`; push once and read the Build (ipa + tests) and Mirror workflows; fix and push again if needed.
- [ ] **Step 3: Report** with the screenshots, what each screen shows, what CI cannot prove (real device, real Cloudflare), and the Swift status (compiled by CI only after this push).
