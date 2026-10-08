# Need Review

A Spanish hub page listing words flagged as weak. Artifacts flag them through the `review.flag` capability; only the person clears them.

## Pieces

```
Features/Review/
  Storage/   ReviewNeed (SwiftData), ReviewRepository (+ SwiftDataReviewRepository)
  Library/   NeedReviewView (the page), ReviewNeedBanner (highlight on a word's detail page)
App/CapabilityProviders.swift   review.flag, review.list (the only code that sees both Word and ReviewNeed)
```

- `Features/Review` never imports `Word` or `Artifacts`; `Features/Artifacts` never imports `ReviewNeed`. `headword` and `translation` on a need are snapshots taken at flag time.
- **One open need per word.** Re-flagging an open need: `flagCount += 1`, `score = max(old, new)`, note/source/snapshots refreshed. A flag after "Mark as learned" starts a fresh open need; cleared needs are kept as history.
- Caps: note 200 characters, score clamped to 0…1 (NaN becomes 0.5), headword/translation 200.
- `AppEnvironment.syncReviewNeeds()` deletes needs (open or cleared) whose word no longer exists. It runs on launch (`RootView`), when the Spanish hub appears and when the Need Review page appears.

## Capabilities

| Name | Class | Args | Returns |
|---|---|---|---|
| `review.flag` | write | `{words:[{id? or key?, score? = 0.5, note?}]}`, 1–50 words | `{flagged, unresolved:[ids or keys not in the library]}` |
| `review.list` | read | `{}` | open needs `[{wordID, headword, translation, score, note, flagCount, updatedAt}]`, weakest first |

- Unknown words are listed in `unresolved`, not errors. The same word twice in one call is one flag with the higher score.
- A dry run (draft preview) returns `{flagged: 0, unresolved: []}` and writes nothing.
- `review.flag` needs approval like any write; spec artifacts cannot request it, but can bind a table to `review.list` (read).
- Artifacts cannot clear needs.

## Screens

- **Hub row** "Need Review" with the open count (also its accessibility value).
- **Page**: open needs by score descending then `updatedAt` descending. Tap a row to open the word (`router.openWord`); the check button or a swipe marks it learned. Empty state when none.
- **Highlight**: `RootView` injects `ReviewNeedBanner` into `WordDetailHost`. It shows "Needs review", the note and a Mark as learned button; library tiles are unchanged.

## Testing

- `ReviewRepositoryTests`, `ReviewCapabilityTests` (real registry, in-memory stores), `ReviewSyncTests`.
- `ReviewUITests` uses `-UITestSeedReview`, which flags the seeded word `palabra0` (needs `-UITestSeed`).
