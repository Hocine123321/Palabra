# Agent guide

Read this before changing code. It explains what the app is, where things live, and which names must not change.

## What this app is

A native iPhone (SwiftUI + SwiftData, iOS 17) **study app** powered by the user's own Google AI (Gemini) API key. It started as a Spanish-vocabulary app and is being generalized into a general study app.

- **Today:** one feature, **Vocabulary** — a library of Spanish words, each with AI-generated examples, meaning, forms, similar words, a follow-up chat and pronunciation audio.
- **Study tab (new):** a second top-level tab next to Spanish (`RootView` is a `TabView` with Spanish, Study, Solve and Settings tabs). It holds flashcards with spaced repetition: decks, a review screen, and AI card generation from pasted notes. Library words are mirrored into a system "Vocabulary" deck. See "Study (flashcards)" below. Quiz Gen and photo/PDF input are planned follow-ups; further tools go in their own folder under `Features/` (see "Adding a feature").
- **Naming:** the app is called **Palabra** and keeps that name. It is the product name, not a claim that the app is Spanish-only: the Xcode target/module, the `Palabra/` folder, the display name and the bundle id all stay `Palabra`. Do not propose or start a rename.

Known weaknesses and follow-ups from the last code review are in `docs/REVIEW.md`; check it before starting related work and update it when an item is fixed.

## Layout

```
Palabra/
  App/                  entry point, dependency container (AppEnvironment), Router, RootView
  Core/                 shared by every feature — should not know about vocabulary
    AI/                 AIClient protocol, GeminiClient, StubAIClient, AIError, AIModel
    Audio/              WAVAudio (normalizes Gemini TTS output), PronunciationPlayer (AVAudioPlayer wrapper)
    Capabilities/       JSONValue, Capability, CapabilityRegistry, CodeFence: the registry artifacts and the chat both use
    Catalogue/          model catalogue, model filters, default-model picker, API-key entry
    DesignSystem/       Theme, glass surfaces, motion, shared components
    Localization/       SupportedLanguage (app language / AI language: en, ar)
    SRS/                SRSScheduler (pure SM-2-style spaced repetition; no UI, no storage)
    Storage/            KeychainStore (API key), SettingsStore (UserDefaults), OrganizerSettings, AssistantSettings
  Features/
    Onboarding/         first-run screen
    Spanish/            hub page list (SpanishHomeView), the Spanish tab's stack root
    Solve/              Solve tab: on-device nerdamer + optional Wolfram|Alpha + Gemini fallback, on-device photo OCR, saved answers (see "Solve")
    Settings/           settings + model picker (app-wide, not vocabulary-specific)
    Artifacts/          AI-built tables/charts/roadmaps/checklists, saved and versioned (Spanish hub page)
      Domain/           ArtifactKind, GrantPolicy, AIUsageLimiter (the registry itself lives in Core/Capabilities)
      Storage/          Artifact, ArtifactVersion, ArtifactStateEntry (SwiftData), ArtifactRepository
      Spec/             SpecBlock, SpecValidator, SpecBindLoader, SpecStateStore, SpecRenderer + views
      AI/               ArtifactEnvelope, ArtifactPrompts, ArtifactGenerator (generateJSON, delimited envelope)
      Library/          list, draft sheet (preview/refine/save), detail (update/versions/delete), ArtifactApprovalCard
      App/              app artifacts: BridgeDispatcher (pure), PalabraBridge, ArtifactSandbox (CSP, rules, shim, NavigationGate), AppRendererView, error log
    Chat/               the assistant: saved conversations that act on the app through the capability registry
      Storage/          ChatConversation (SwiftData), ChatTurn/ChatAction (JSON), ChatRepository
      AI/               ChatPrompts, ChatReplyParser
      Conversation/     ChatSession (the model/action loop)
      Library/          ChatListView, ChatView
    Review/             Need Review: flagged words (Spanish hub page)
      Storage/          ReviewNeed (SwiftData), ReviewRepository
      Library/          NeedReviewView (page), ReviewNeedBanner (word-detail highlight, injected by RootView)
    Study/              flashcards + spaced repetition (the second tab)
      Storage/          Deck, Card, ReviewLog (SwiftData), CardRepository
      Domain/           CardDraft, VocabularyCardEntry, DeckCounts, StudyRoute, grade/interval labels
      AI/               StudyPrompts, CardGenerator (notes -> card drafts via generateJSON)
      Review/           ReviewViewModel (one session over a queue), ReviewView
      Decks/            Study home, deck detail, new-deck-from-notes flow
      Exam/             Study → Exam: Domain/ (ExamTypes, AnswerMatcher, ExamBuilder), Session/ (ExamSession), AI/ (ExamAI), Storage/ (ExamResult, ExamRepository), Speech/ (SpeechListener), Views/
    Vocabulary/         the Spanish word library
      Domain/           WordContent, WordKey, ContentValidator, Honeycomb, chat types, LibraryOrganization (tag/section cleanup)
      Organization/     LibraryOrganizer (batch AI re-organize), LibrarySections (grouping/search), sectioned view, organize sheet, organization settings
      Storage/          Word (SwiftData), WordRepository, VocabularyLibraryExporter (old JSON format, read-only), WordBackup (backup records), WordQueueItem/WordQueueRepository (offline queue), WordWriter (shared save logic)
      AI/               VocabularyPrompts, VocabularyResponseSchema
      Pronunciation/    PronunciationService, PronunciationButton
      Queue/            WordQueueProcessor (drains the offline queue), QueuedWordsBanner
      Library/          VocabularyLibraryView (the home screen), grid/list, add-word bar
      AddWord/          add / regenerate flow and preview sheet (AddWordFlow has a `.queued` phase for offline)
      WordDetail/       word screen
      Chat/             follow-up chat about one word
  Resources/            Localizable.strings (ar)
PalabraTests/           unit tests; folders mirror Palabra/ (App, Core, Vocabulary, Support)
PalabraUITests/         UI tests (stubbed AI)
project.yml             XcodeGen project definition (the .xcodeproj is generated, never committed)
docs/features/          notes on shipped features
docs/archive/superpowers/ ORIGINAL Spanish-only design and plan — historical, not current
```

New files under `Palabra/`, `PalabraTests/` and `PalabraUITests/` are picked up automatically by XcodeGen; there is no project file to edit.

## Rules

1. **Dependency direction:** `Features/*` may use `Core/*`. `Core/*` must not use `Features/*`. Features must not use each other's internals.
2. **Known places where this is not true yet** (deliberate leftovers, fix them when the first non-vocabulary tool needs the same code — do not copy them):
   - `AIClient` now has a generic `generateJSON(prompt:systemInstruction:schema:...)` for new tools to build on. It still also carries vocabulary-specific methods (`generateWord`, `sendChat`, `organizeWords`) and uses `WordContent`, `ChatMessage`, `ContentValidator`, `VocabularyPrompts`, `VocabularyResponseSchema`. A general tool needs a generic "send this prompt/schema, get JSON or text back" method on the client, with the vocabulary calls built on top of it.
   - `Theme` (tile tints) calls `WordKey.tintIndex`.
   - `SettingsStore.LibraryLayout` is a vocabulary UI setting stored in Core.
   - `AppEnvironment` also owns `artifacts` (`ArtifactRepository`) and `capabilities` (the `CapabilityRegistry`, built by `CapabilityProviders` in `App/`); it also owns `review` (`ReviewRepository`); `PalabraApp`'s schema also lists `Artifact`, `ArtifactVersion`, `ArtifactStateEntry`, `ReviewNeed`.
   - `AppEnvironment` owns the `WordRepository`, the `WordQueueRepository`/`WordQueueProcessor`, the `CardRepository`, the `PronunciationService` and `requestPronunciationIfConfigured(for: Word)`; `Router.Destination` has `wordDetail`, `artifacts`, `artifactDetail` and `needReview` cases; `PalabraApp` builds the SwiftData schema from every persisted model (`Word`, `WordQueueItem`, `Deck`, `Card`, `ReviewLog`, the three artifact entities, `ReviewNeed`, `ChatConversation`, `SolveEntry`, `ExamResult`).
3. **Errors and AI calls** return `Result<_, AIError>`; nothing in the UI should crash on a bad AI response.

## Names that must NOT be changed (they are on users' devices)

Changing any of these silently loses the user's saved words, settings or API key unless you also write a migration and test it:

- Bundle id `dev.palabra.app` and the Keychain service `dev.palabra.app.google`.
- The SwiftData entity `Word` and its stored property names (`spanish`, `key`, `searchKey`, `contentData`, `rawJSON`, `chatData`, `pronunciationAudio`, `category`, `tagsData`, ...). Renaming a `@Model` class or stored property changes the on-device schema.
- UserDefaults keys in `SettingsStore.Keys` (including `organizerSettings` and `assistantSettings`, JSON blobs that must keep decoding when fields are added; `OrganizerSettings` has a tolerant decoder).
- The JSON keys inside `WordContent` (including `spanish` / `english` / `translation` on examples) — stored data and Gemini's response schema both use them.
- The SwiftData entities `Deck`, `Card` and `ReviewLog` and their stored properties (including the raw-value strings `kindRaw` / `phaseRaw` / `gradeRaw`; their enum raw values are append-only), and the `newCardsPerDay` key in `SettingsStore.Keys`.
- The SwiftData entities `Artifact`, `ArtifactVersion` and `ArtifactStateEntry` and their stored properties (including `kindRaw`, `grantedData`, `requestedData`, `payload`, `valueData`); the `ArtifactKind` raw values `"spec"` / `"app"` are append-only, and so are the JSON blobs in `grantedData` / `requestedData` (`[String]` of capability names).
- The SwiftData entity `ChatConversation` and its stored properties (`turnsData` is JSON `[ChatTurn]` with tolerant decoding: add fields, never rename).
- The SwiftData entity `SolveEntry` and its stored properties (`query`, `queryKey`, `resultData`, `createdAt`, `updatedAt`; `resultData` is JSON `SolveResult` with tolerant decoding) and the UserDefaults key `wolframUsage`; the Keychain account `wolfram-app-id`.
- The SwiftData entity `ReviewNeed` and its stored properties (including `statusRaw`); the `ReviewStatus` raw values `"open"` / `"cleared"` are append-only.
- The library backup file: `Core/Backup/ArchiveContainer.swift` (header `PLBR`, footer `PLBE`, version byte) and the metadata `LibraryArchive` (`format: "Palabra Library"`, `version`) written by `LibraryBackupService`. New fields in `LibraryArchive`, `WordBackup`, `StudyBackup`, `ChatBackup` must be optional so older files keep reading; a layout change bumps the version. The old JSON envelope (`app: "Palabra"`, `version: 1`) is read-only in `VocabularyLibraryExporter`; old exports must keep importing.
- The SwiftData entity `ExamResult` and its stored property names (`configData`, `questionCount`, `scoreSum`, `durationSeconds`, `recordsData`), the JSON inside `configData` / `recordsData` (`ExamConfig`, `ExamAnswerRecord`: new fields optional, decoding tolerant), the `ExamSkill` / `ExamQuestionKind` raw values (stored in records, append-only), and `ExamBackup` (inside `LibraryArchive.exams`, a property-list header: new fields optional).
- The SwiftData entity `WordQueueItem` and its stored property names (`inputWord`, `existingWordID`, `existingCreatedAt`, `languageRaw`, `createdAt`, `statusRaw`, `attempts`, `lastErrorMessage`) — same reasoning as `Word`: a rename changes the on-device schema and loses whatever's mid-flight in someone's offline queue.

It is fine — and encouraged — to rename Swift *types* and files that are not persisted (that is how `Prompts` became `VocabularyPrompts`).

## User-visible text

- Localization is keyed by the English string: `Resources/ar.lproj/Localizable.strings` maps the exact English text to Arabic. If you change a UI string, change its key there too.
- UI tests find elements by their English text, so changing a string means updating the UI tests as well.
- The user picks the app language and the AI-output language independently (`SupportedLanguage`).

## Build, test, verify

- `scripts/check-conventions.sh` (run by CI first) rejects direct `withAnimation`/`.animation(` use, `try? context.save()`, hardcoded `Color(hex:)` and numeric corner radii; run it locally before pushing.
- Builds and tests run in GitHub Actions on a macOS runner (`.github/workflows/build-ipa.yml`). The `ipa` job produces the unsigned IPA (`Palabra-unsigned-ipa` artifact); the `tests` job runs unit and UI tests.
- When the archive or a unit-test step fails, the workflow prints the compiler / test errors as an annotation on the failed job, so they can be read through the GitHub API without downloading logs.
- A green `ipa` job means the app compiles; it does not prove the app works on a device. Check behaviour changes with tests.
- Swift settings: `SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY targeted`.

## Design system: "Recortes & Glass" (use these, don't hardcode)

A quiet warm-neutral ground, muted paper cutouts behind Liquid Glass, and one accent: Claude Orange (`Theme.accent`, #D97757). Glass only floats (bars, bottom accessories, sheets, capsule controls). Content inside glass sits on flat fills (`Theme.fill`, `.innerFill()`), never on nested glass.

- **Screens:** `Form`/`List` screens call `.glassScreen()` and wrap rows in `Section { }.themedSection()` (thin material rows over the cutouts). `ScrollView` screens put `ScreenBackdrop(style:)` behind the content (`.calm` for lists/forms, `.rich` for hubs/onboarding/empty states).
- **Cards:** `GlassSurface` for primary cards; `.glassCard()` for views that lay out their own padding; `.glassCapsule()` for chips/controls; `.glassAccessory()` for a floating bottom bar (add word, ask about this word) via `.safeAreaInset(edge: .bottom)`. Hero surfaces use `CutoutCard(tint:)` (word hero, flashcard, Solve answer) with muted `Theme.tileTints`; ink text on tints is `Theme.onTint`. Decorative shapes are `.accessibilityHidden(true)`.
- **Colour:** orange for fills, tint and selection; use `Theme.accentDeep` for orange *text* or small icons (the plain accent is too light on the light ground). Do not add `.tint(Theme.accent)`: `RootView` sets it. Never hardcode hex values in views.
- **Radii (concentric):** `Theme.Radius.small` (10), `.medium` (20: inner controls, bubbles, rows), `.card` (28), `.sheet` (40: hero cutouts), `.pill` (capsules). No numeric corner radii.
- **Type:** SF Rounded via roles `Theme.Font.display / title / heading / rowTitle / tile`; body copy uses system text styles. No bundled fonts.
- **Buttons:** one full-width main action per screen uses `.buttonStyle(.primary)` (orange capsule). Secondary actions: `.glassAction`; round icon buttons: `.glassIcon`. Compact inline actions may use `.bordered` / `.borderedProminent` with `.buttonBorderShape(.capsule)`.
- **Motion:** never call `withAnimation` or `.animation(...)` directly. Use `Motion.animate(...)` and `.animation(Motion.reduced(...), value:)` so Reduce Motion is honoured.
- **Tabs:** `RootView` has four tabs (Spanish, Study, Solve, Settings; `AppTab`) on the native `TabView` (the system draws the floating Liquid Glass bar; UI tests rely on `app.tabBars.buttons[...]`). `router.openSettings()` switches to the Settings tab from anywhere, so banners and prompts never push Settings onto the wrong stack. The Spanish tab's stack root is `SpanishHomeView` (a card hub, rows are `NavigationLink`s by `Router.Destination` value with `spanishRow.*` identifiers); `Router.path` is `[Router.Destination]` and `openWord` stacks `.vocabulary` under `.wordDetail`. New hub pages add a `Router.Destination` case and a card in `SpanishHomeView`.

## Layout safety (learned the hard way)

- A custom `Layout` must never report a size wider than the width it was proposed, and should propose that width to its children (`FlowLayout` does). Otherwise one long AI string stretches the whole screen.
- Never use AI-supplied strings as `ForEach` identity (`id: \.label`, `id: \.self`): duplicates break the view. Use the enumerated offset.
- AI output that is displayed must be capped in `ContentValidator` (see the Word Forms limits).

## Branch workflow

- All work happens directly on `main`. The `BETA` branch no longer exists.
- Pushes to `main` run CI (`build-ipa.yml`: the `ipa` build and all unit and UI tests). Check it after every push, and fix a red build before starting new work.

## Resilience (retries, backup key, per-error reactions)

- Every screen calls `environment.ai`, which in the live app is a `ResilientAIClient` decorating `GeminiClient`. Do not add retry loops in screens; add a case to `ErrorStrategy` instead.
- `ErrorStrategy.next` is pure and decides the reaction per error: offline waits for the network (not counted as an attempt; but when `connectivity.isConnected` is already true, `ResilientAIClient` treats it as a transient failure with backoff, then asks, so it can never spin), transient errors retry with doubling waits, quota/invalid/denied keys switch to the backup key immediately (waiting never helps), blocked/setup errors stop, everything else asks the person.
- When automatic tries run out the person picks Try Again, Retry with Longer Waits, or Stop (`ResilienceCenter.ask`, shown by `ResilienceOverlay`). Background work (`environment.backgroundAI`) never asks; its failures appear under Settings > Reliability > Recent Problems.
- The backup key lives in its own Keychain account (`api-key-fallback`). `KeyHealth` benches a failing key (rate limit 1 min, quota 1 h, rejected 24 h) and prefers the main key again as soon as it recovers.
- Tests use `AppEnvironment(... resilient: false)` by default, so retries never slow them. Resilience is tested with `ScriptedAIClient` and an injected `sleep`.
- **Model health and backup models.** `ModelHealthStore` (persisted, thread-safe) learns per model from every real request (`ResilientAIClient.learn`, also on the `failingFast`/auto-retry-off paths) and from `ModelProbe` (Test buttons): working (6 h), rate limited (1 min), quota used (1 h), unstable (2 min), not available (24 h). Only model-specific errors count; offline, bad key and blocked prompts don't. `ModelPickerView` shows icon-plus-word badges and has a "…" menu with Test All Models and an only-working filter (`canTest`, text models only); `ModelValueLabel` shows a chosen model with its mark in Settings rows. `ModelHealth.status` never turns an expired problem back into "working": only a fresh success does.
- When the chosen model fails, `ErrorStrategy.next(... hasBackupModel:)` can return `.switchModel`: quota and removed models switch at once, a rate limit after one patient retry, outages after the retries, always before the backup key. `BackupModelPicker.candidates` orders: the model chosen in Reliability, models marked working, then flash, flash-lite, the rest; limited ones are skipped. A switch does not bench the key, at most `maxModelSwitches` (3) models are tried per request, a known-limited chosen model is skipped before the request is sent, and TTS and `failingFast` requests never switch. A key switch starts over with the requested model. `RetryPolicy.switchModelEnabled` / `backupModelID` hold the settings.
- 429 is two different things: `GeminiClient.isQuotaExhausted` reads the message to tell a per-minute limit (wait) from a spent daily quota (switch key).

## Offline word queue

- Adding or regenerating a word while offline doesn't fail: `AddWordFlow` checks `environment.connectivity.isConnected` before calling the AI, and also treats a `.offline` failure (the connection dropped mid-request and `ResilientAIClient` gave up) the same way — both enqueue a `WordQueueItem` and move the sheet to the `.queued` phase instead of a dead-end error.
- `WordQueueProcessor.drain(environment:)` works the queue one item at a time, oldest first, using `environment.backgroundAI` (quiet — no retry dialog). It's triggered from `RootView` on launch and on returning to the foreground, from `AddWordFlow` right after queuing, and from the Retry button on a failed row in `QueuedWordsBanner`; calling it while already draining is a no-op.
- Saving a generated result is shared, not duplicated: both `AddWordFlow.save()` and `WordQueueProcessor` go through `WordWriter.commit(content:mode:environment:)`.
- **Foreground only.** There's no iOS background-execution hookup — a queue left while the app is backgrounded or killed resumes draining next time the app opens, not before. `WordQueueProcessor.run()` resets any item orphaned `.processing` by an interrupted previous run back to `.pending` for exactly this reason.
- A `.failed` item (a setup problem like a missing key, or a non-retryable `AIError`) stops being retried automatically; the person retries or removes it from `QueuedWordsBanner`.

## Library organization

- Each `Word` has an optional `category` (one section) and `tagsData` (JSON `[String]`). `nil` category = not organized yet. Both are part of the library backup (`WordBackup`); restoring never overwrites a section or tags the word already has.
- "Re-organize Library" (`LibraryOrganizer`) works in batches of `batchSize`, writes nothing until every batch succeeds, and sends known section names to later batches so names are reused. Words the AI omits go to "Other".
- New words are placed by `AppEnvironment.requestOrganizationIfConfigured` (respects `OrganizerSettings.autoOrganizeNewWords`). Regenerating a word keeps its placement.
- Search matches word, translation, section and tags; `#tag` searches tags only.

## Study (flashcards)

- Engine: `Deck` / `Card` / `ReviewLog` (SwiftData, plain UUID references, no `@Relationship`). `SRSScheduler` is pure and takes `now`; every grade writes the card and a `ReviewLog` in one save (`CardRepository.record`).
- **Boundary:** Study never imports `Word`. `AppEnvironment.syncVocabularyCards()` is the only place that knows both sides: it reads the library and calls `CardRepository.syncVocabulary` with plain `VocabularyCardEntry` values. It is idempotent (keyed on `sourceWordID`), keeps scheduling state, updates text when a word is regenerated, and deletes cards (and logs) of deleted words. It runs on launch and whenever the Study tab appears. A word without a translation gets no card.
- A mirrored word is exactly one basic card (headword -> translation). No reversed or cloze cards yet.
- Card text is AI/user content: display it with `Text(verbatim:)`, never use it as `ForEach` identity (`CardDraft` carries its own `id`), and cap it in `CardGenerator.parse`.
- `CardGenerator` uses the generic `generateJSON` (no new `AIClient` method, so the mocks did not change). Nothing is saved until the person confirms the preview.
- Daily new-card cap: `SettingsStore.newCardsPerDay` (default 20). `studyQueue` subtracts cards first reviewed today.
- Pronunciation on mirrored cards is injected from the app (`VocabularyCardPronunciation` in `RootView`), so Study stays free of Vocabulary types.
- Spec: `docs/features/study-flashcards.md`.

## Study → Exam

- An exam asks about the person's own library words. `AppEnvironment.examWords()` (`App/AppEnvironment+Exam.swift`) is the one place that turns `Word` into the plain `ExamWord` (Study never imports `Word`, same rule as `syncVocabularyCards`).
- **Nothing in an exam needs AI.** `ExamBuilder` (pure, generic over a `RandomNumberGenerator`; tests use `SeededGenerator`) makes every question from the words' own translations, examples, forms and similar words; wrong options come from the whole library. Kinds: meaning/reverse/similar-word choice, matching, type the Spanish/the meaning, fill the blank (cloze from an example), choose the form, put words in order, listening (the phone's own voice via `SentenceSpeaker`, free), speaking (`SpeechListening`; only offered when the recognizer is available), plus the AI-only writing kinds. `ExamCapabilities`/`ExamConfig.kinds` decide what is offered.
- Grading is in `AnswerMatcher`/`ExamSession`, never in a view: exact 1.0, accents missing 0.75, one or two letters off 0.5 (by word length), wrong 0; matching loses a share per mistake; order scores the share of words in place. English answers may drop "to/the/a", brackets are not part of an answer.
- **AI is optional and additive** (`ExamConfig.useAI`, needs a key and model; `AppEnvironment.examAI()` is nil otherwise). `ExamAI` uses the generic `generateJSON` through `AppEnvironment.examGenerate` (no new `AIClient` method): fresh cloze/translation sentences for exactly the words the exam will ask (same seed → `plannedWords`), grading written answers (`ExamGrading`; if the AI fails the person grades themselves), and a coach summary on the result screen. Everything it returns is parsed tolerantly, clipped (`ExamAILimits`) and shown with `Text(verbatim:)`. `StubAIClient` answers the grade and coach schemas.
- Speaking: `SpeechListener` (SFSpeechRecognizer es-ES, on device when possible, AVAudioEngine). `project.yml` has the microphone and speech usage strings (Arabic in `InfoPlist.strings`). UI tests use `StubSpeechListener` (`-UITestSpeech <text>`).
- Results: `ExamResult` (SwiftData, newest 100 kept) with `ExamAnswerRecord`s; `ExamRepository.wordStats` feeds "Weakest first" and the "Needs practice" list. A finished or ended-early exam is saved once (`ExamSessionView.saveOnce`). Missed words can be practiced again (`ExamSource.words`) or flagged to Need Review (`AppEnvironment.flagExamMisses`). Exams travel in the backup (`LibraryArchive.exams`, `LibraryBackupService` with an optional `ExamRepository`; answers are re-pointed to the imported words' ids).
- Routes: `StudyRoute.examSetup/.exam(ExamConfig)/.examHistory/.examResult(UUID)`. UI identifiers: `examTile`, `startExamButton`, `examSkill-<raw>`, `examOption-<n>`, `examTypedField`, `examCheckButton`, `examNextButton`, `examVerdict`, `examScoreCard`.

## Artifacts

- **The registry is the only door.** An artifact reaches app data only through `CapabilityRegistry.call`; the AI's manual is generated from the same registry. A new capability is one `Capability` in a provider in `App/CapabilityProviders.swift` and nothing else.
- `Features/Artifacts` never imports `Word`, `Deck`, `Card` (or a later `ReviewNeed`). `App/CapabilityProviders.swift` is the only file that sees both `WordRepository` and `ArtifactRepository`; data crosses as `JSONValue`.
- **Spec artifacts never prompt:** they only bind `.read` capabilities, which are auto-granted (`GrantPolicy`). **App artifacts always prompt** (`ArtifactApprovalCard`) for read/write/ai capabilities; `.local` is auto-granted. The effective grant is requested ∩ granted + local, and an update asks only for the delta.
- **App sandbox:** the web view uses a non-persistent data store, a CSP injected into the HTML, two content-blocking rules (`^https?://`, `^wss?://`) and `NavigationGate` (one navigation only). Do not loosen any of these without updating `ArtifactSandboxTests`. The shim (`ArtifactSandbox.shimScript`) is the only injected JS.
- **Bridge dispatch stays pure:** `BridgeDispatcher.handle` has no WebKit types so it is unit-tested; `PalabraBridge` only converts and forwards. Every call goes through `CapabilityRegistry.call`. `ai.generate` is rate limited per `sessionID` (`AIUsageLimiter`).
- JavaScript inside the web view is not covered by CI; only the Swift side and the stubbed approval/save flow are.
- AI strings render with `Text(verbatim:)`, `ForEach` uses the enumerated offset, and everything is capped in `SpecValidator`. Truncate, don't reject.
- The generator makes one automatic retry (truncated / invalid spec / malformed envelope). Do not add retry loops in screens.
- `StubAIClient`'s artifact envelope must stay valid for the real prompt/parser/validator: `StubArtifactTests` enforces it. New `AIClient` methods need a `MockAIClient` stub (`generateJSON` recording is additive).
- Spec: `docs/features/artifacts.md`.

## Chat

- The assistant acts only through `CapabilityRegistry.call`; its toolset is every `.read` and `.write` capability (never `.local` or `.ai`). Reads run at once; **a write never runs without the person's consent**: by default the confirmation card's Apply, or, only when the person switched off Settings → Assistant → "Ask Before Making Changes", at once. Do not add any other way around that.
- Settings → Assistant (`AssistantSettings`, Core/Storage; key `assistantSettings`, tolerant decoder, JSON blob that must keep decoding): reply length, standing instructions, ask-before-changing, and per-group switches (`AssistantToolGroup`: library, words, study, review; a capability's group is its name prefix, `stats.*` counts as library; a capability with no group is always on). Groups are stored as the *disabled* ones. `ChatSession` reads the settings on every run and every approval, so a switch applies at once; a switched-off capability is absent from the manual and refused with "switched off in Settings". A new capability prefix needs a case in `AssistantToolGroup.group(forCapability:)` if it should be switchable.
- `ChatSession` owns the loop (max 4 model calls per message, 5 calls per reply, one automatic retry for a malformed actions block). Screens only call `send`, `approvePending`, `declinePending`, `retry`, `clear`.
- The chat uses the generic `generateJSON` with the transcript rendered as text (no new `AIClient` method). Its protocol marker is `---ACTIONS---`; `StubAIClient` keys on it, so keep the two in sync (`ChatUITests`, `SmokeUITests`).
- `Features/Chat` never imports `Word`, `Deck`, `Card` or `ReviewNeed`; `RootView.openChat` (App layer) is where a word's old chat is imported. `Word.chatData` and `AIClient.sendChat` are no longer used by any screen (kept for stored data and their tests).
- A new capability needs a `describe` closure when it is a write, so the card reads well. Spec: `docs/features/chat.md`.

## Need Review

- `Features/Review` never imports `Word` or `Artifacts`. Snapshots (`headword`, `translation`) are copied at flag time by `CapabilityProviders`, the only file that sees both `Word` and `ReviewNeed`.
- One open need per word; re-flagging upserts (`flagCount`, max score). Only the person clears a need (artifacts have no capability for it).
- The word-detail highlight is injected from `RootView` into `WordDetailHost` (the `VocabularyCardPronunciation` pattern), so Vocabulary stays independent of Review.
- `AppEnvironment.syncReviewNeeds()` drops needs of deleted words; call it wherever `syncVocabularyCards` is called.
- Spec: `docs/features/need-review.md`.

## Solve

- `Features/Solve` is self-contained (never imports `Word`, `Deck`, `Card`). Own tab and `NavigationStack` (`SolveRootView`, `SolveRoute`). Everything hangs off `SolveTool` (`environment.solve`).
- **Solver chain** (`CompositeMathSolver`): `LocalMathSolver` (nerdamer in JavaScriptCore, `Resources/Math/solver.js` is the dispatcher; it answers only what it can verify numerically, else "unsupported") → `WolframSolver` (only if an App ID is saved) → `GeminiMathSolver` (`AIClient.generateJSON` with a schema; credentials via the late-bound `GeminiLink`, wired in `AppEnvironment.wireSolve()`). Gemini does not do code execution. Steps offered as `ai:<answer>` are written by Gemini; Wolfram's own offer stays `Result__Step-by-step solution`. `SolveResult.source` says who answered; only Wolfram answers/steps count toward `SolveUsage`. A hung JS run can't be killed, only abandoned after 8 s (new context).
- Wolfram|Alpha takes text only; photos go through on-device Vision (`VisionTextRecognizer`), then `MathInputNormalizer`, then an editable box. Photos are read by Gemini (`GeminiTextRecognizer`, the person's key, downscaled to 1600 px by `PhotoPreparer`) and fall back to on-device Vision (`FallbackTextRecognizer`) when there is no key, no connection or Gemini fails. Wolfram|Alpha and the on-device engine only ever get text. The camera permission text and the Solve footer must keep saying so.
- **Never spend a call on the person's behalf.** Solving checks the saved answer first (`SolveEntry`, `queryKey`); steps are a button ("Uses one more free call."). Network failures and a refused key are not counted by `SolveUsage`; success and "no result" are.
- "Powered by Wolfram|Alpha" shows whenever Wolfram answered (result screen) or an App ID is saved (home), per API terms.
- `SolveResult` / `SolvePod` / `SolveSubpod` are stored as JSON in `SolveEntry.resultData`: tolerant decoders, add fields, never rename. Pod images are stored as bytes (Wolfram's image URLs expire).
- The App ID is optional and the person's own, in the Keychain (`KeychainStore.wolfram()`). UI tests: `-UITestStub` uses `StubMathSolver` / `StubTextRecognizer`; `-UITestNoSolveKey` starts without an App ID.
- Spec: `docs/features/solve.md`.

## Adding a feature (for example a study tool)

1. Create `Palabra/Features/<Name>/` with the same sub-folders it needs (`Domain`, `Storage`, `AI`, screens) and a matching `PalabraTests/<Name>/`.
2. Take the AI client, model, language, API key and design system from `Core` via `AppEnvironment`. Do not build services inside views.
3. Put anything the tool persists in its own SwiftData model, registered where `PalabraApp` builds the schema. Adding a new model is safe; changing an existing one is not (see above).
4. Add a `Router.Destination` case, or give the tool its own tab/stack like Study (`RootView` is a `TabView` with Spanish, Study, Solve and Settings tabs; Study owns its `NavigationStack` and `StudyRoute`).
5. Use feature-prefixed names for anything that could be mistaken for app-wide (`VocabularyLibraryView`, not `LibraryView`).
6. Add tests, push, and make sure both CI jobs compile.
