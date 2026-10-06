# Artifacts, Spanish hub and Need Review — design

Status: approved in conversation (4 sections), awaiting written-spec review.
Date: 2026-10-06. Source of truth for code is the live repo; this spec describes the target.

## 1. Purpose and success criteria

**Stated by the user**

- The `Vocabulary` main tab becomes `Spanish`. It holds a list of pages: Vocabulary (moved), Artifacts (new), Need Review (new).
- The user asks the AI for tables, charts, layouts, learning roadmaps and interactive apps. Results are saved as **artifacts**, can be reopened, expanded and updated later.
- Artifacts are more capable than the same thing built outside the app: they can read app data, call the app's AI, and write results back.
- Example loop: a conversation-practice artifact builds a simulated conversation from library words, finds weak words, flags them. Flagged words are highlighted on their detail page and listed in a new **Need Review** page.
- Example: a tracker artifact reads words learned per day/week from the app.
- The platform gives the AI a toolset and the instructions for using it, so artifacts can communicate with the app.

**Assumptions (correct if wrong)**

- Generation uses the existing Gemini key through `environment.ai` (`ResilientAIClient`). No backend.
- The app owns every write to its own data. Artifacts can only request writes through named capabilities.
- Plain artifacts (a table) and app-like artifacts (a simulator) use the same capability layer.

**Success**

1. "Make me a table of Spanish days and weeks" produces a saved, reopenable artifact with no permission prompt.
2. "Build a conversation practice app from my library words" produces an interactive artifact that calls `library.words`, `ai.generate`, `review.flag`; flagged words show a highlight on their detail page and appear in Need Review.
3. "Chart my words added per day" produces a chart that stays current without re-running the AI.
4. Adding a capability to the app makes it available to the AI with no prompt edits.

## 2. Decomposition

Five plans, in order. Each ends in working, CI-checked software on `main`.

| Plan | Delivers |
|------|----------|
| A | Spanish hub (`SpanishHomeView`, tab rename, router). Only the Vocabulary row exists. |
| B1 | Platform + **spec** artifacts end to end: registry, storage, `library.*`, `stats.*`, `storage.*`, generator, preview, Artifacts page and row. |
| B2 | **App** artifacts: sandboxed web view, bridge, `ai.generate`. |
| C | Need Review: `ReviewNeed`, `review.*`, detail-page highlight, page and row. |
| D+ | Further capability packs, one per plan. |

## 3. Architecture

```
Palabra/Features/Artifacts/      never imports Word, Deck, Card, ReviewNeed
  Domain/    Artifact types, ArtifactKind, Capability, CapabilityRegistry, GrantPolicy, JSONValue
  Spec/      SpecBlock (Codable), SpecValidator, SpecRenderer (SwiftUI + Swift Charts)
  App/       ArtifactSandbox, PalabraBridge, AppRenderer (WKWebView)
  AI/        ArtifactPrompts, ArtifactGenerator, ArtifactHTMLLint, ArtifactEnvelope (parser)
  Storage/   Artifact, ArtifactVersion, ArtifactStateEntry (SwiftData), ArtifactRepository
  Library/   Artifacts page: list, create sheet, preview, detail, approval sheet
Palabra/Features/Review/         never imports Word or Artifacts
  Storage/   ReviewNeed (SwiftData), ReviewRepository
  Library/   NeedReviewView, ReviewBadge
Palabra/Features/Spanish/        SpanishHomeView (hub list)
Palabra/App/CapabilityProviders.swift   the only code that knows both sides
```

- Rule 1 of `AGENTS.md` holds: Features use Core; Features do not use each other's internals. `CapabilityProviders` (in `App/`, like `syncVocabularyCards`) is the only place that sees `Word` and `ReviewNeed`; it hands the registry plain `JSONValue`s.
- The registry is the single source of truth: it dispatches calls for both renderers and generates the AI manual. A new capability is learnable by the AI automatically.
- Swift Charts is a system framework, not a third-party dependency.

## 4. Data model (new SwiftData entities; additive, existing schemas untouched)

Registered in `PalabraApp`'s schema next to `Word`, `WordQueueItem`, `Deck`, `Card`, `ReviewLog`. Plain UUID references, no `@Relationship` (as Study).

```swift
@Model Artifact           // id, title, kindRaw ("spec"|"app", append-only), currentVersion: Int,
                          // grantedData: Data (JSON [String] of capability names), createdAt, updatedAt
@Model ArtifactVersion    // id, artifactID, number: Int, payload: Data (spec JSON or UTF-8 HTML),
                          // requestedData: Data (JSON [String] manifest), prompt: String, createdAt
@Model ArtifactStateEntry // artifactID, key: String, valueData: Data, updatedAt
@Model ReviewNeed         // id, wordID, headword, translation, score: Double, note: String,
                          // sourceArtifactID: UUID?, flagCount: Int, statusRaw ("open"|"cleared", append-only),
                          // createdAt, updatedAt, clearedAt: Date?
```

- Payload caps: stored payload ≤ 64 KB. Latest 20 versions kept per artifact; older pruned.
- **Restore** copies an old version's payload into a new version (history is append-only).
- `ArtifactStateEntry`: key ≤ 64 chars, total ≤ 256 KB per artifact; overflow returns `failed("storage full")`.
- `ReviewNeed`: one `open` record per `wordID`. Re-flagging upserts: `flagCount += 1`, `score = max(old, new)`, note and source refreshed. `headword`/`translation` are snapshots because Review cannot import `Word`. `note` capped at 200 characters; `score` clamped to 0…1.
- These names become persisted names: add them to the "must NOT be changed" list in `AGENTS.md` (enum raw values append-only).

## 5. Capability contract

```swift
enum CapabilityClass { case read, write, ai, local }   // local = the artifact's own storage
struct ArtifactSession: Sendable { let artifactID: UUID?; let dryRun: Bool }  // nil id = unsaved draft
struct Capability: Sendable {
    let name: String
    let kind: CapabilityClass
    let summary: String         // plain language; goes into the AI manual and the approval sheet
    let argsSchema: JSONValue   // goes into the AI manual
    let returnsSummary: String  // goes into the AI manual
    let dryRunValue: JSONValue? // required for .write; returned instead of running the handler in dryRun
    let handler: @Sendable (JSONValue, ArtifactSession) async -> Result<JSONValue, CapabilityError>
}
enum CapabilityError: Error { case unknown, notGranted, badArgs(String), failed(String), rateLimited }
```

`JSONValue` is a Codable, Sendable enum. Bridge reply: `{ok:true,value}` or `{ok:false,error:{code,message}}`.

`CapabilityRegistry.call(name:args:session:granted:)` checks in order: unknown → not granted (`.local` always granted) → args size ≤ 64 KB → handler (or `dryRunValue` for `.write` when `session.dryRun`). Each handler validates its own args and returns `badArgs`. `manual() -> String` renders every capability for the prompt.

### Catalog

| Capability | Class | Args | Returns |
|---|---|---|---|
| `library.words` | read | `{limit?: 1…500 (default 100), offset?, category?, tag?}` | `[{id, key, spanish, translation, partOfSpeech, category, tags, createdAt}]` (no audio, no chat) |
| `library.word` | read | `{id}` or `{key}` | the word's `WordContent` JSON (keys unchanged) plus the fields above |
| `stats.wordsPerDay` | read | `{days: 1…365}` | `[{day:"YYYY-MM-DD", count}]` oldest first, zero-count days included, device calendar/time zone |
| `stats.wordsPerWeek` | read | `{weeks: 1…104}` | `[{weekStart:"YYYY-MM-DD", count}]` oldest first, zero weeks included, calendar's first weekday |
| `storage.get` / `storage.set` / `storage.remove` | local | `{key}` / `{key, value}` / `{key}` | value or `null` / `{}` / `{}` |
| `ai.generate` | ai | `{prompt ≤ 8000 chars, schema?, temperature?}` | `{text}` |
| `review.flag` (plan C) | write | `{words:[{id?, key?, score? = 0.5, note?}]}` ≤ 50 words, each needs `id` or `key` | `{flagged: Int, unresolved: [String]}` — unknown words are listed, not errors |
| `review.list` (plan C) | read | `{}` | open needs `[{wordID, headword, translation, score, note, flagCount, updatedAt}]` |

- Stats derive from `Word.createdAt`; no new tracking.
- `ai.generate` runs through `environment.ai` with a fixed app-side system instruction (answer the prompt only, Spanish-learning context). Limits per artifact per open session (session = while its screen is presented; an unsaved draft counts per preview): 10 calls per rolling minute, 100 total → `rateLimited`. AI errors map to `failed(<AIError guidance message>)`.
- `.local` storage in dry run uses an in-memory scratch instead of the database.
- Artifacts cannot clear needs. Only the user can, from Need Review.

## 6. Permissions

- The AI declares a manifest (`requests`: capability names) with each payload. `SpecValidator` drops unknown names.
- `GrantPolicy.required(kind:requested:)`:
  - **spec** artifacts may request only `.read` (for `bind`) and `.local`; both are auto-granted, so they never prompt. `SpecValidator` drops `.write` and `.ai` names from a spec manifest.
  - **app** artifacts: `.local` is auto-granted; `.read`, `.write`, `.ai` need approval.
- Approval is one sheet in plain language (each capability's `summary`), shown in the preview before first interaction. The result is stored in `Artifact.grantedData` on Save.
- On update only the delta is prompted. Denied capabilities return `notGranted`. The user may still Save, or Discard / Restore an older version.
- The registry re-checks the grant on every call, regardless of renderer. The effective grant is `requested ∩ granted` plus `.local`.

## 7. Renderers

### Spec renderer (`kind = spec`)

Payload is JSON `{blocks:[SpecBlock]}`. Block types and fields:

- `heading {level 1…3, text}`, `text {text}`, `list {ordered, items}`
- `table {columns:[{title, field?}], rows? | bind?}`
- `chart {style:"bar"|"line", labels?, series? | bind?, labelField?, valueField?}`
- `stats {tiles:[{label, value}]}` (inline only)
- `checklist {id, items:[{text}]}`, `roadmap {id, steps:[{title, detail?}]}` — ticks/step completion persist in `ArtifactStateEntry` under `spec.<blockID>`
- `columns {children}`, `section {title, children}`

`bind` = `{capability, args}`, allowed on `table` and `chart` only, only to `.read` capabilities. Table rows come from an array of objects via each column's `field`; a chart takes one series from `labelField`/`valueField`. Bound data is fetched on appear and on returning to the foreground; there is no live observation.

`SpecValidator` caps: ≤ 60 blocks, depth ≤ 4, table ≤ 20 columns × 200 rows, chart ≤ 500 points, string length caps per field, unique `id`s for `checklist`/`roadmap`. AI strings render with `Text(verbatim:)`; `ForEach` uses enumerated offsets, never AI strings, as identity. The renderer honours layout direction (RTL).

### App renderer (`kind = app`)

- Payload is a single self-contained HTML file; loaded with `loadHTMLString(_, baseURL: nil)`.
- `ArtifactSandbox`: `WKWebsiteDataStore.nonPersistent()`; a `WKContentRuleList` blocking all http/https/ws loads (compiled before the first load); an injected CSP meta (`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:`); navigation off the document cancelled; `javaScriptCanOpenWindowsAutomatically = false`.
- `PalabraBridge`: `WKScriptMessageHandlerWithReply` named `palabra`; main frame only; message ≤ 256 KB; per-call timeout 30 s (120 s for `ai.generate`). The shim injected at document start exposes `palabra.call(name, args) -> Promise`, `palabra.granted`, `palabra.theme` (CSS variables from `Theme`), `palabra.locale` (`"en"|"ar"`), `palabra.dir`. `window.onerror` and rejected calls are forwarded to the artifact's in-memory error log.
- Dispatch is a pure function (message in, reply out) so it is unit-testable without a `WKWebView`.

## 8. Generation and update

**Wire format**: one `generateJSON(schema: nil)` call returning plain text:

```
{"kind":"spec"|"app","title":"…","requests":["library.words", …]}
---PAYLOAD---
<spec JSON, or raw single-file HTML>
---END---
```

Delimiters (not JSON-escaped HTML) avoid corruption of embedded HTML. A missing `---END---` means the 8192-token output cap was hit → `ArtifactGenError.truncated`.

- `ArtifactPrompts.systemInstruction(registry:language:allowedKinds:)`: until plan B2 ships `allowedKinds` is `[.spec]` and the prompt forbids `app`; output format, spec block catalog (derived from `SpecBlock`), app rules (single file; no external URLs; use `storage.*`, not `localStorage`; use `palabra.call`; handle `ok:false`; theme CSS variables; honour `palabra.locale`/`palabra.dir`), size budget (app HTML ≤ 20 KB), then `registry.manual()`. Visible artifact text uses the AI-output language setting; Spanish words stay Spanish. The user's request goes in `prompt`, never in the system text.
- `ArtifactGenerator.create(request:)` and `.update(artifact:change:) -> Result<ArtifactDraft, ArtifactGenError>`. Update sends the current payload plus the change request and receives the full new payload. No diff/patch mode in v1. **Known limit:** an app near the output cap cannot be extended in place; the error says it is too large and suggests asking for a simpler version.
- `ArtifactHTMLLint` rejects: `<script src=http…>`, `<link href=http…>`, `localStorage`, a payload without `<html`.
- Retry budget: at most **one** automatic retry in total, for truncation or lint failure, with the concrete problem appended to the prompt. A second failure is returned as an error.
- Runs through `environment.ai`, so the resilience overlay applies. Offline shows the existing offline guidance; there is no generation queue.
- **Preview before save** (as Study): nothing persists until the user confirms. The draft renders in the real renderer with `dryRun = true` (`.write` returns `dryRunValue`; `.local` uses in-memory scratch; reads and `ai.generate` are real). Buttons: Save, Refine (re-prompt with a change request), Discard. Update: Keep writes a new `ArtifactVersion` and bumps `currentVersion`; Discard leaves the old version untouched.
- **Fix with AI**: the artifact screen shows the logged runtime errors and an action that feeds them into the update flow.
- All results are `Result<_, ArtifactGenError>`; `AIError` is wrapped. No UI path may crash on a bad response (`AGENTS.md` rule 3).

## 9. Need Review

- `ReviewRepository`: `flag(entries:)` (upsert), `openNeeds()`, `markLearned(id:)`, `deleteOrphans(validWordIDs:)`.
- `AppEnvironment.syncReviewNeeds()` deletes needs whose word no longer exists; runs wherever `syncVocabularyCards` runs.
- **Detail-page highlight**: `RootView` injects a badge-and-note view into `WordDetailHost` (the `VocabularyCardPronunciation` pattern), so Vocabulary never imports Review. Highlight is on the detail page only; library tiles are unchanged.
- **Need Review page**: open needs sorted by `score` descending then `updatedAt` descending. Row actions: open the word (`router.openWord`), Mark as learned.
- Closing the loop: a practice artifact calls `review.list` to focus on weak words.

## 10. Spanish hub

- `AppTab.vocabulary` → `.spanish`; tab label "Spanish".
- Stack root is `SpanishHomeView`: list rows Vocabulary, Artifacts (plan B1), Need Review with open-count badge (plan C). Rows are added by the plan that delivers their destination; no dead rows.
- `Router.Destination` gains `.vocabulary`, `.artifacts`, `.artifactDetail(UUID)`, `.needReview`. `openWord(id)` sets `path` to `[.vocabulary, .wordDetail(id)]` so Back lands on the library.
- `ar.lproj/Localizable.strings` gains "Spanish", "Artifacts", "Need Review" (keyed by English text). UI tests that start on the library gain an `openVocabulary()` helper; tests matching the "Vocabulary" tab label are updated.

## 11. Error handling summary

| Situation | Behaviour |
|---|---|
| Truncated / lint failure | one automatic retry, then error with guidance |
| Malformed envelope or spec | `ArtifactGenError`, nothing saved |
| Unknown / ungranted capability | `{ok:false}` to the artifact; logged |
| Bad args, oversized message | `badArgs`; message dropped over 256 KB |
| `ai.generate` rate limit | `rateLimited` |
| Offline generation | existing offline guidance |
| Word deleted while flagged | orphan sync removes the need |

## 12. Testing

Compiled by eye only; every change needs a real CI run.

- **Unit**: registry (grants, dry run, unknown name, size cap); `JSONValue` codec; bridge dispatcher as a pure function; `GrantPolicy`; envelope parser (truncation, missing header, bad kind); `ArtifactHTMLLint`; `SpecValidator` caps and bind rules; generator retry budget; update prompt includes the current payload; `ArtifactRepository` (versions, prune at 20, restore); `ReviewRepository` (upsert, orphan sync, clamp); `review.flag` provider (id and key resolution, unresolved reporting, 50-word cap); `stats.*` (empty library, day/week boundaries, clamping); `library.words` (paging; no audio/chat keys); manual completeness (every registered capability appears in `manual()`).
- **Prompt-sent pattern** (this repo's placeholder-text bug class): `MockAIClient.generateJSON` does not record inputs today. Add `generateJSONCalls` and an optional `generateJSONScript` as additive stored properties (protocol unchanged, no stub breaks). `ArtifactGeneratorTests` assert the recorded `prompt` contains the user's literal request and `systemInstruction` contains every capability name.
- **UI** (stub AI): create spec artifact → preview → save → listed; `-UITestSeedReview N` shows the detail-page badge and the Need Review row; `-UITestArtifactFixture` loads an app artifact whose HTML calls `library.words` and prints a marker (accessibility reads of web content may be flaky; keep it isolated).
- JS behaviour inside the web view is not covered by CI.

## 13. Review focus (inputs the spec must handle)

1. Word deleted while flagged (orphan sync, no crash on the detail page).
2. Same word flagged by two artifacts (single open record, `flagCount` 2, max score).
3. Call to an ungranted or unknown capability.
4. Oversized args / bridge message; malformed bridge message.
5. Empty library for `library.words`, `stats.*`, and a practice artifact.
6. Denied grant on update, then restore.
7. RTL layout in spec and app artifacts.
8. Truncated generation.
9. `ai.generate` flood (rate limit) and offline `ai.generate`.

## 14. Non-goals

Diff/patch updates; artifact export or sharing; background execution; artifact-to-artifact calls; artifacts clearing needs; library tile highlight; external libraries or CDNs; generation queue while offline; iPad layouts.

## 15. Documentation to update with the code

`AGENTS.md` (layout, persisted names, rules for Artifacts/Review/Spanish hub), `docs/features/artifacts.md` and `docs/features/need-review.md` (new), README feature list if present.
