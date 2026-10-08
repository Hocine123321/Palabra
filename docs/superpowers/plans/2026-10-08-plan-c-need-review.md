# Plan C: Need Review

Spec: `docs/superpowers/specs/2026-10-06-artifacts-design.md` §4, §5, §9, §10. The live repo wins over the spec.

Rules: `Features/Review` never imports `Word` or `Artifacts`; `Features/Artifacts` never imports `ReviewNeed`; `CapabilityProviders` (App/) is the only file that sees both. No `withAnimation`. AI strings use `Text(verbatim:)`. Arabic keys are the English text. CI is the only compiler.

## Task 1: model and repository (Features/Review/Storage)
- `ReviewNeed` (@Model: id, wordID, headword, translation, score, note, sourceArtifactID, flagCount, statusRaw, createdAt, updatedAt, clearedAt). `ReviewStatus` open/cleared (append-only raw values).
- `ReviewRepository` (@MainActor protocol) + `SwiftDataReviewRepository` (`inMemory()`): `flag(_:now:)` upsert on the open need of a word; `openNeeds()` (score desc, updatedAt desc); `openNeed(wordID:)`; `openCount()`; `markLearned(id:now:)`; `deleteOrphans(validWordIDs:)`.
- Caps: note 200 chars, score clamped 0…1, headword/translation 200.
- Tests: `ReviewRepositoryTests`.

## Task 2: capabilities (App/CapabilityProviders)
- `review.flag` (write): `{words:[{id?|key?, score?=0.5, note?}]}` ≤ 50; unknown words go to `unresolved`; dry run returns `dryRunValue`. `review.list` (read).
- `registry(... review:)` defaults to an in-memory repo. `AppEnvironment.review`, `syncReviewNeeds()`.
- Tests: `ReviewCapabilityTests`, update registry-names test, `ReviewSyncTests`.

## Task 3: UI
- `Router.Destination.needReview`; `RootView` resolves it and injects the highlight banner into `WordDetailHost` (so Vocabulary never imports Review).
- `NeedReviewView` (list, open word, Mark as learned, empty state), `ReviewNeedBanner`, hub row with open-count badge.
- Schema, `PalabraApp` reset, `-UITestSeedReview`, Arabic strings, localization test, UI test.

## Task 4: docs
- `docs/features/need-review.md`, `AGENTS.md` (layout, persisted names, rules), artifacts doc capability list. Push, fix CI, deliver zip.
