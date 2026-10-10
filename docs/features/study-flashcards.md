# Study: Flashcards + spaced repetition (spec)

Status: implemented (slice 1), compiled by eye only; needs a real CI run.

## Goal
Second top-level tool. One card engine for (a) Spanish library words and
(b) any subject via AI-generated decks from pasted notes. Biggest study
bottleneck is remembering, so this ships first; Quiz Gen and photo/PDF
input are follow-up specs.

## Decisions (from brainstorm)
- Engine design A: library words are mirrored one-way into cards in a
  system "Vocabulary" deck. `Word` schema is NOT touched.
- A mirrored word = ONE basic card (front = headword, back = translation).
  No reversed or cloze cards in this spec.
- Scheduler: SM-2-style, grades Again / Hard / Good / Easy.

## Data (new @Model types, registered beside `Word` in PalabraApp's schema)
No @Relationship; plain UUID references, like the rest of the codebase.

    Deck      id, name, kind(.vocabulary | .user), createdAt
    Card      id, deckID, front, back, kind(.basic), sourceWordID?,
              due, interval, ease, reps, lapses, state(new|learning|review), createdAt
    ReviewLog id, cardID, grade, reviewedAt, prevInterval, newInterval

ReviewLog exists now so Quiz Gen / a dashboard can read history later.
Persisted raw values are append-only once shipped (same rule as `Word`).

## Scheduler
`Core/SRS/SRSScheduler`: pure `next(state: SRSState, grade: Grade, now: Date) -> SRSState`.
No SwiftData/UI dependency. `now` is injected. Interval/ease bounds clamped.

## Layout
    Palabra/Core/SRS/SRSScheduler.swift
    Palabra/Features/Study/{Domain,Storage,AI,Review,Decks}/
    PalabraTests/Study/

## Boundary rule
`Study` never imports `Word` or Vocabulary internals. Mirroring is a reconcile, not
per-event hooks: `AppEnvironment.syncVocabularyCards()` reads the library and calls
`CardRepository.syncVocabulary([VocabularyCardEntry])` with plain values. It is idempotent
(keyed on `sourceWordID`), keeps scheduling state, updates text when a word is regenerated,
and removes cards (and logs) for deleted words, so add / regenerate / delete / import /
delete-all are all covered without touching each call site. Runs on launch and whenever the
Study tab appears. A word with an empty translation gets no card. Mirror problems never
block adding or editing a word (nothing in the Vocabulary flows calls it).

## Navigation
- `RootView` -> `TabView`: Vocabulary | Study.
- Vocabulary tab keeps its existing `NavigationStack` + `Router` unchanged.
- Study has its own stack and `StudyRoute` path (`@State` in `StudyRootView`); `Router.Destination` does not grow.
- Study home: decks with due counts + "Review all due".

## Review screen
Front -> tap flips -> 4 grade buttons showing next interval. One save writes
the Card update + ReviewLog. Queue: due first, then new cards up to a daily
cap (default 20; new `SettingsStore.Keys` entry, additive only).
Pronunciation on vocabulary-deck cards via an injected closure (no
Vocabulary import).

## AI card generation (notes -> deck)
- Flow: paste text -> `CardGenerator` -> preview list -> edit/delete ->
  confirm. Nothing persisted before confirm.
- Built on existing `generateJSON` + response schema. NO new `AIClient`
  method (so `MockAIClient` / `ScriptedAIClient` need no new stubs).
- Goes through `ResilientAIClient`; returns `Result<_, AIError>`. No retry
  logic in views (use `ErrorStrategy`).
- Validate like `ContentValidator`: cap card count and field length; empty or
  invalid output -> inline error, nothing saved.
- ForEach identity uses enumerated offsets, never AI-provided strings.

## Localization
Every new UI string gets an `ar.lproj/Localizable.strings` key and uses
`LocalizedStringKey` (not `String`) for display text.

## Tests
- `SRSSchedulerTests`: pure, fixed `now`; each grade, clamping, lapse.
- `CardRepositoryTests`: upsert idempotency, delete-on-word-removal, backfill.
- `CardGeneratorTests`: `MockURLProtocol` asserts the pasted notes text is
  actually present in `request.httpBody` (placeholder-text bug class),
  plus validation caps and empty-output cases.
- UI: extend `-UITestSeed` to seed cards; `StubAIClient` returns a canned
  card set; a review-flow XCUITest (flip, grade, queue empties).

## Out of scope (follow-up specs)
1. Multimodal input (photo/PDF) on `AIClient`, then cards from photos.
2. Quiz Gen over decks (MCQ / short answer), feeding ReviewLog.
3. Reversed / cloze cards, dashboard.


## Refinements (study page)

- **Study home:** a *Today* card (progress ring of answers given today against answers + still due + new, due/new counts, streak, last-7-days bars, **Review All Due**), then one card per deck with a started-progress bar and a play button for that deck, and a "Make a deck from notes" tile. Stats come from `CardRepository.reviewStats(now:)` -> `StudyStatsCalculator` (pure: streak counts consecutive days with an answer, ending today or yesterday).
- **Review:** a progress bar over the session (`ReviewViewModel.progress`; an Again card that returns counts again) and, on finish, a summary (reviewed, correct %, streak). The "All caught up" title is kept (UI tests).
- **Deck detail:** cards / due / new header, per-card status (New, Due, or time until due), search, **Add Card** (user decks, `AddCardView`, duplicates refused) and swipe-to-delete (`CardRepository.deleteCard`, user decks only: the Vocabulary deck mirrors the library).
- No stored property changed (`DeckCounts`, `Card`, `ReviewLog` are as before), so no migration.
