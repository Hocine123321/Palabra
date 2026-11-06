# Artifacts: Claude export prompt and import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Copy a complete prompt out of Palabra for Claude/ChatGPT, paste the answer back, and run it as an artifact; app artifacts from external AIs may be up to 124 KB.

**Architecture:** The export is the generator's own system instruction plus the request, so it cannot drift. Import reuses `ArtifactEnvelopeParser` and the generator's build step (lint, capability filter, spec validation) with a larger app byte limit and no AI call. Storage limit becomes per kind (app 126,976 B, spec 65,536 B).

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest. Compiled by eye only here; CI is the compiler.

**Spec:** `docs/superpowers/specs/2026-11-06-artifacts-claude-export-design.md`

## Global Constraints

- Gemini path keeps 65,536 B (`ArtifactLimits.maxPayloadBytes`) and the "At most 20 KB" prompt line.
- External app cap: 124 KB = 126,976 bytes (`ArtifactLimits.maxExternalAppBytes`). Export prompt tells the AI "At most 120 KB".
- Spec artifacts keep 65,536 B. Lint rules (no external URLs, no `localStorage`), sandbox, registry and approval flow are unchanged.
- Every new UI string needs an Arabic key in `Palabra/Resources/ar.lproj/Localizable.strings` (`LocalizationTests`).
- Export and import must work with no API key.
- Do not touch `MockAIClient` (no `AIClient` change).
- Commit to `main` after each task. Commit messages end with the two attribution lines from the session reminder.

## Review Focus

- Claude's answer wrapped in chat prose and a code fence ("Here is your app: ```html …```"): must still import (Task 3).
- Pasting with no API key or offline: import must not need credentials (Task 4).
- Update mode: pasted app for a spec artifact (or the reverse) must fail, never silently switch kind (Task 4).
- Huge paste (≥ 1,000,000 characters): rejected quickly as too large, no hang (Task 3).
- Restoring an old 100 KB app version must work, since `restore` goes through `addVersion` (Task 1).

## File Structure

- Modify `Palabra/Features/Artifacts/Storage/ArtifactRepository.swift`: `ArtifactLimits.maxExternalAppBytes`, `ArtifactLimits.payloadLimit(for:)`, per-kind check.
- Modify `Palabra/Features/Artifacts/AI/ArtifactHTMLLint.swift`: `check(_:limit:)`, `.tooLarge(limit:)`.
- Modify `Palabra/Features/Artifacts/AI/ArtifactPrompts.swift`: `appMaxKB` parameter, `exportPrompt`.
- Modify `Palabra/Features/Artifacts/AI/ArtifactGenerator.swift`: `appByteLimit`, `importDraft`.
- Create `Palabra/Features/Artifacts/AI/ArtifactImport.swift`: normalizes a pasted answer.
- Modify `Palabra/Features/Artifacts/Library/ArtifactDraftModel.swift`: `exportPrompt()`, `importExternal(_:)`.
- Create `Palabra/Features/Artifacts/Library/ArtifactImportSheet.swift`; modify `ArtifactDraftView.swift`.
- Modify `Palabra/Resources/ar.lproj/Localizable.strings`, `docs/features/artifacts.md`.
- Tests under `PalabraTests/Artifacts/` (existing files extended, `ArtifactImportTests.swift` and `ArtifactExportPromptTests.swift` new).

---

### Task 1: Per-kind storage limit and lint limit

**Files:** modify `ArtifactRepository.swift`, `ArtifactHTMLLint.swift`; tests `ArtifactRepositoryTests.swift`, `ArtifactHTMLLintTests.swift`.

**Interfaces:**
- Produces: `ArtifactLimits.maxExternalAppBytes = 126_976`; `ArtifactLimits.payloadLimit(for kind: ArtifactKind) -> Int` (`.spec` → `maxPayloadBytes`, `.app` → `maxExternalAppBytes`); `ArtifactHTMLLint.check(_ html: String, limit: Int = ArtifactLimits.maxPayloadBytes)`; `ArtifactHTMLLintError.tooLarge(limit: Int)` whose `detail` names the limit.

- [ ] **Step 1: Write failing tests.** In `ArtifactRepositoryTests`: `testAppPayloadUpTo126976BytesIsAcceptedAndOverIsRejected` (create `.app` with 126,976 → success; 126,977 → `.payloadTooLarge`), `testSpecPayloadStillLimitedTo65536` (`.spec` 65,537 → `.payloadTooLarge`), `testAddVersionUsesTheArtifactsKind` (100,000 B onto an `.app` succeeds, onto a `.spec` fails), `testRestoreOfA100KBAppVersionWorks` (create app v1 at 100,000 B, add v2 small, `restore(versionNumber: 1)` succeeds and `currentVersion == 3`). In `ArtifactHTMLLintTests`: update `testRejectsOver65536Bytes` to expect `.tooLarge(limit: 65_536)`; add `testExplicitLimitIsHonoured` (`check(html100KB, limit: 126_976)` succeeds; 126,977 bytes fails with `.tooLarge(limit: 126_976)`); update `testEveryErrorHasADetail` to the new case.
- [ ] **Step 2: Run** `xcodebuild test -scheme Palabra -only-testing:PalabraTests/ArtifactRepositoryTests -only-testing:PalabraTests/ArtifactHTMLLintTests` (CI equivalent). Expected: FAIL (does not compile).
- [ ] **Step 3: Implement** the interfaces above. `create` checks `ArtifactLimits.payloadLimit(for: kind)`; `addVersion` checks `payloadLimit(for: artifact.kind)`. Lint compares against `limit`.
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(artifacts): per-kind payload limit, lint limit parameter`.

### Task 2: Export prompt

**Files:** modify `ArtifactPrompts.swift`; create `PalabraTests/Artifacts/ArtifactExportPromptTests.swift`.

**Interfaces:**
- Produces: `ArtifactPrompts.systemInstruction(registry:language:allowedKinds:appMaxKB: Int = 20)` (the app rule line reads "At most \(appMaxKB) KB."); `ArtifactPrompts.exportPrompt(userPrompt: String, registry: CapabilityRegistry, language: SupportedLanguage) -> String`.

- [ ] **Step 1: Write failing tests** (`ArtifactExportPromptTests`, use the real `CapabilityRegistry` the other tests build): `testExportContainsSystemRulesManualAndRequest` — output contains `ArtifactPrompts.systemInstruction(registry:…, allowedKinds: [.spec, .app], appMaxKB: 120)` verbatim, contains `registry.manual(including: [.read, .write, .ai, .local])`, contains the user prompt, contains `"---PAYLOAD---"` and `"---END---"`; `testExportSaysAtMost120KB` and `testGeminiInstructionStillSays20KB` (default call contains "At most 20 KB" and not "120 KB"); `testExportEndsWithEnvelopeOnlyInstruction` (last paragraph contains "no code fences" and "no commentary").
- [ ] **Step 2: Run** `-only-testing:PalabraTests/ArtifactExportPromptTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `exportPrompt` = system instruction (kinds `[.spec, .app]`, `appMaxKB: 120`) + blank line + `REQUEST:` + user prompt + closing instruction: answer with the artifact in the exact output format, nothing before or after, no code fences, no commentary. The Gemini call site keeps the default.
- [ ] **Step 4: Run** the new tests plus `ArtifactGeneratorTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(artifacts): export prompt for external AIs`.

### Task 3: Import normalization and non-AI draft building

**Files:** create `AI/ArtifactImport.swift`, `PalabraTests/Artifacts/ArtifactImportTests.swift`; modify `ArtifactGenerator.swift`.

**Interfaces:**
- Consumes: Task 1 `ArtifactHTMLLint.check(_:limit:)`.
- Produces: `ArtifactGenerator.appByteLimit: Int` (init-able property, default `ArtifactLimits.maxPayloadBytes`; `buildApp` passes it to the lint); `ArtifactGenerator.importDraft(_ text: String, fixedTitle: String?, expectedKind: ArtifactKind?, userPrompt: String) -> Result<ArtifactDraft, ArtifactGenError>` (parse envelope, then the existing `build`); `enum ArtifactImport { static let maxInputCharacters = 1_000_000; static func normalize(_ text: String, registry: CapabilityRegistry) -> String }`.

- [ ] **Step 1: Write failing tests** (`ArtifactImportTests`, generator built with `allowedKinds: [.spec, .app]`, `appByteLimit: ArtifactLimits.maxExternalAppBytes`, a registry containing `library.words`):
  - `testEnvelopeIsAccepted`: valid app envelope → `.app` draft, title from header.
  - `testFencedEnvelopeIsAccepted`: the same inside ```` ```text ```` fences.
  - `testBareHTMLBecomesAnAppWithTitleFromTitleTag`: `<!doctype html><html><head><title>Verb Trainer</title></head>…` → title `"Verb Trainer"`, kind `.app`.
  - `testChatProseAroundFencedHTMLIsStripped`: `"Here is your app:\n```html\n<html>…</html>\n```\nEnjoy!"` → success, payload starts with `<html` and ends with `</html>`.
  - `testRequestsAreInferredAndFilteredToRegisteredCapabilities`: HTML calling `palabra.call("library.words")` and `palabra.call("made.up")` → requests `["library.words"]`.
  - `testExternalURLAndLocalStorageStillRejected` (`.invalidApp` for each).
  - `testAppOver124KBIsRejectedAndUnder1ishAccepted`: 126,976 B accepted, 126,977 B → `.invalidApp`.
  - `testGeminiLimitStillApplies`: generator with default `appByteLimit` rejects a 66,000 B app.
  - `testHugePasteIsRejectedQuickly`: 1,000,001 characters → `.failure(.invalidApp)`/too large without parsing (assert elapsed < 1 s using `measure`-free `Date` diff).
  - `testNoHTMLAndNoEnvelopeIsMalformed`: `"hello"` → `.malformedEnvelope`.
  - `testExpectedKindMismatchFails`: spec-envelope pasted with `expectedKind: .app` → `.malformedEnvelope`.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/ArtifactImportTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `normalize`: if the text contains `---PAYLOAD---` return it unchanged; otherwise find the range from the first `<!doctype` or `<html` (case-insensitive) to the last `</html>` and wrap it as an envelope (header JSON built with `JSONSerialization`: kind `app`, title from the first `<title>…</title>` else "Untitled", requests from the regex `palabra\.call\(\s*["']([A-Za-z0-9_.]+)["']`, deduplicated); with no such range return the text unchanged so the parser reports `.malformedEnvelope`. `importDraft` first rejects input longer than `maxInputCharacters` with `.invalidApp("it is far too large")`, then `ArtifactEnvelopeParser.parse(ArtifactImport.normalize(text, registry: registry))`, then `build`.
- [ ] **Step 4: Run** `ArtifactImportTests`, `ArtifactGeneratorTests`, `ArtifactEnvelopeTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(artifacts): import a pasted answer from an external AI`.

### Task 4: Draft model

**Files:** modify `ArtifactDraftModel.swift`; extend `PalabraTests/Artifacts/ArtifactDraftModelTests.swift`.

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces: `ArtifactDraftModel.exportPrompt() -> String?` (nil unless the request has ≥ `minRequestLength` characters); `func importExternal(_ text: String)`; `Operation.importExternal(String)` so `retry()` replays the import without any AI call.

- [ ] **Step 1: Write failing tests** (build the model the way the existing tests do, with a `MockAIClient` and no API key):
  - `testExportPromptForCreateIncludesFormatLineAndRequest`: format `.app`, request "verb trainer" → prompt contains `"FORMAT: build this as kind \"app\""` and `"verb trainer"`.
  - `testExportPromptForUpdateIncludesCurrentPayload`: update mode on a saved app → contains `"CURRENT PAYLOAD:"` and the stored HTML.
  - `testExportPromptNilWhenRequestTooShort`.
  - `testImportWorksWithoutAnAPIKeyAndMakesNoAICalls`: `importExternal(validEnvelope)` → `phase == .preview`, `draft?.kind == .app`, `MockAIClient.generateJSONCalls.isEmpty`.
  - `testImportKeepsRequestAsPromptAndFallsBackToLabel`: saved version prompt equals the typed request, or `"Imported from an external AI"` when empty.
  - `testImportFailureShowsFailedAndRetryReplaysImport`: garbage → `.failed(.malformedEnvelope)`; `dismissFailure()` returns to `.input`; `retry()` leaves no AI call recorded.
  - `testUpdateImportKeepsKindAndSavesAsNewVersion`: pasting an app into an app artifact saves version 2; pasting a spec envelope into it fails.
  - `testImportAsksApprovalForNewCapabilities`: imported app requesting `library.words` → `needsDecision == true`.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/ArtifactDraftModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `exportPrompt()` builds the user prompt (create: `format.apply(to: trimmed request prefix maxInput)`; update: `ArtifactPrompts.updatePrompt` with the current snapshot) and calls `ArtifactPrompts.exportPrompt`. `importExternal` builds `ArtifactGenerator(ai: environment.ai, registry: environment.capabilities, language: environment.aiLanguage, allowedKinds: [.spec, .app], appByteLimit: ArtifactLimits.maxExternalAppBytes)`, calls `importDraft` (in update mode with the snapshot's title and kind), then mirrors the success/failure tail of `execute` (set `draft`, reset `decided` when `pending` is non-empty, `phase = .preview` / `.failed`). No credential lookup.
- [ ] **Step 4: Run** `ArtifactDraftModelTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(artifacts): draft model export and import`.

### Task 5: UI, Arabic strings, docs

**Files:** create `Library/ArtifactImportSheet.swift`; modify `ArtifactDraftView.swift`, `ar.lproj/Localizable.strings`, `PalabraTests/*/LocalizationTests.swift`, `docs/features/artifacts.md`.

**Interfaces:** Consumes `ArtifactDraftModel.exportPrompt()`, `importExternal(_:)`.

- [ ] **Step 1: Write the failing test.** In `LocalizationTests` add `testArabicStringsHaveExternalAIKeys` with keys: "Copy prompt for Claude", "Prompt copied", "Paste Claude's answer", "Paste the answer here", "Paste from clipboard", "Use this answer", "Imported from an external AI". Run `-only-testing:PalabraTests/LocalizationTests`. Expected: FAIL.
- [ ] **Step 2: Add the Arabic strings** to `Localizable.strings` (same style as neighbours).
- [ ] **Step 3: Build the UI.** In `ArtifactDraftView.inputForm`'s pinned bottom area add a row above Generate: a bordered capsule button "Copy prompt for Claude" (disabled when `exportPrompt()` is nil; copies with `UIPasteboard.general.string`, label switches to "Prompt copied" for two seconds; accessibility id `copyArtifactPromptButton`) and a bordered capsule button "Paste Claude's answer" opening `ArtifactImportSheet` (id `pasteArtifactAnswerButton`). `ArtifactImportSheet(onUse: (String) -> Void)`: a `TextEditor` (id `artifactImportField`), a "Paste from clipboard" button, a primary "Use this answer" button (disabled when empty) that calls `onUse` and dismisses; the view's closure calls `model.importExternal`.
- [ ] **Step 4: Update docs.** In `docs/features/artifacts.md`: limits table (app 124 KB external / 64 KB Gemini and spec), a new "Using Claude or ChatGPT" section (copy prompt, paste answer, accepted forms, no key needed, Gemini refine of apps > 64 KB says "too large to extend"), and the testing note that JavaScript in the web view is not covered by CI. Add the empty-state line to `ArtifactsListView` only if the localization test already covers its key (otherwise skip).
- [ ] **Step 5: Run** `LocalizationTests`, then the full `PalabraTests` target on CI. Expected: PASS. State plainly in the delivery note that this was compiled by eye only and needs a real CI run.
- [ ] **Step 6: Commit** `feat(artifacts): copy prompt for Claude and paste the answer`.

---

## Self-review

- Spec coverage: export prompt (Task 2), import with envelope/HTML/fence (3), update-mode import (4), per-kind 124 KB cap and Gemini 64 KB (1, 3), no change to sandbox/approval (4 test), docs (5). The spec's "requests inferred from `palabra.call`" is in Task 3.
- Types consistent: `payloadLimit(for:)`, `appByteLimit`, `importDraft`, `exportPrompt` used identically across tasks.
- Spec detail adjusted: the spec said import goes "through the existing `ArtifactDraftView` preview"; the plan does that via `ArtifactDraftModel.importExternal`.
