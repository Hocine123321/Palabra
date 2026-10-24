# Code review: weaknesses and follow-ups

Review of `main` at `afb5bfb` (2026-10-19). Done by reading the code; **nothing was compiled or run**, so every fix below is
"compiled by eye" and needs a real CI run. Come back to this file to pick up the open items.

**Not read in depth:** `SettingsView`, the Spec renderer/validator internals, `ArtifactDraft*`, `CapabilityProviders` internals,
`ModelHealth`, `GeminiMathSolver` parsing, `WolframParser`, the design-system views, and the JS (`solver.js`, nerdamer).
Findings here come from the files that were read; absence of a finding is not a clean bill of health.

Status: everything in "Fixed" is changed on `main`; "Still open" lists what was left on purpose and why.

---

## Still open (each is a decision or needs a device, not an oversight)

### O1. Serve app artifacts through a `WKURLSchemeHandler` (Low-Med, needs a device)
- The CSP is still a `<meta>` inserted by `ArtifactSandbox.documentWithCSP`. A real `Content-Security-Policy` header from a custom
  scheme handler would be stronger (no regex, nothing for a `<head>` inside a script string to confuse), but it changes the
  page's origin, storage and how the content rules apply, and CI cannot load a `WKWebView`. Do it with a device at hand.

### O2. Other silent `try?` (Low-Med)
- Word saves are now checked end to end (`WordRepository.flush`, queue items kept on a failed write, a message in the preview
  sheet, import errors). The other repositories still ignore `Persistence.save`'s Bool; the screens would show success after a
  failed write. The ~145 other `try?` (JSON decode of stored blobs and similar) were not reviewed one by one.

### O3. Smaller notes (Low)
- `AIUsageLimiter` still forgets the oldest of 64 sessions (resetting that session's limits). Sessions end when the screen closes,
  so 64 open at once is not realistic; left as is.
- `GeminiClient.maxResponseBytes` refuses a huge reply before it is decoded, but `URLSession.data` has already downloaded it;
  true streaming would cost per-byte async iteration on every reply.
- `Word.content`, `chat` and `tags` are still JSON behind computed properties. The grid and list read stored columns
  (`spanish`, `translation`, `partOfSpeech`, `category`); the detail page decodes once per render; search decodes `tags` per word.
  Add a cache only if a profile shows it.
- `SwiftData...Repository.inMemory()` keeps `try!` and ships in the app target (the app passes real repositories; tests and
  previews call it). An in-memory container can only fail on a programmer error.
- `Streak` and "today" in Study stats still turn over at midnight; scheduling and the daily new-card limit use the 04:00 study day.
- CI: the runner label (`macos-26`) is fixed but Xcode and `brew install xcodegen` are whatever the image has (now printed in the
  log); nothing is cached; no SwiftLint (`scripts/check-conventions.sh` covers the AGENTS.md rules a compiler cannot).
- Chat (for later): there is no destructive write capability today. If one is added it must confirm even when
  "Ask Before Making Changes" is off, because stored content can carry prompt injection.

---

## Fixed in the review pass

| # | Problem | Fix | Files |
|---|---------|-----|-------|
| F1 | **High.** When the phone's network path was "satisfied" but Google was unreachable (DNS failure, captive portal, blocked host, dead VPN), `.offline` meant "wait for the network", which returned at once: the request retried forever with no backoff and no question. | `ResilientAIClient` now backs off (2, 4, 8 s), then asks (or stops, for background work) when the path looks connected. A genuinely lost connection still waits without using up an attempt. Two tests added; the test helper now says whether the path looks connected. | `Core/Resilience/ResilientAIClient.swift`, `ResilientAIClientTests.swift` |
| F2 | If the library on disk could not be opened, the app silently ran on a temporary in-memory store and everything saved was lost on exit. | An alert now says so (English + Arabic). | `App/PalabraApp.swift`, `ar.lproj/Localizable.strings` |
| F3 | UI-test launch arguments were live in release builds: `-UITestReset` deletes the whole library, `-UITestStub` swaps in a stub AI and overwrites the saved API key. | Arguments are read only `#if DEBUG` (the UI tests run in Debug). | `App/PalabraApp.swift` |
| F4 | `counts`, `studyQueue`, `newCardsStudied` and card deletion loaded **every card and every review log** into memory; `RootView` runs them on launch, on each tab change and on foreground. | Count and predicate queries, chunked `IN` lists, and a guard for the fetch-limit-0 trap. Same results (existing tests unchanged); two tests added. | `Features/Study/Storage/CardRepository.swift`, `CardRepositoryTests.swift` |
| F5 | `KeychainStore.save` deleted the key before adding the new one, so a failed add lost the saved key. | Updates in place first; only adds when nothing exists. | `Core/Storage/KeychainStore.swift` |
| F6 | `WordQueueProcessor`: a cancelled drain finishing late cleared the task reference and `isDraining` of the next drain, allowing two drains at once. | A run id guards both. | `Features/Vocabulary/Queue/WordQueueProcessor.swift` |
| F7 | Artifact sandbox: CSP lacked `form-action` and `base-uri` (they do not fall back to `default-src`), and a `<head>` inside an HTML comment received the policy instead of the real head. | Both directives added; comment-aware insertion. Three tests added. | `Features/Artifacts/App/ArtifactSandbox.swift`, `ArtifactSandboxTests.swift` |
| F8 | AGENTS.md says displayed AI output must be capped, but examples, explanations, translations, usage and similar-word text were not. | Generous caps (clip, never reject); normal replies are untouched. Two tests added. | `Features/Vocabulary/Domain/ContentValidator.swift`, `ContentValidatorTests.swift` |
| F9 | Import accepted entries with a blank headword. | Skipped and counted. Test added. | `Features/Vocabulary/Storage/WordRepository.swift`, `SwiftDataWordRepositoryTests.swift` |
| F10 | A hard-coded hex colour in a view (design-system rule); a duplicate `"A to Z"` key in the Arabic strings with two different values. | `Theme.paper`; the duplicate removed (the later value, which was the one in effect, is kept). | `Core/DesignSystem/Theme.swift`, `SolveResultView.swift`, `Localizable.strings` |
| F11 | README said "Planned: a second page of AI study tools" and listed three folders. | Updated to what exists. AGENTS.md notes the offline rule change and points here. | `README.md`, `AGENTS.md` |
| F12 | Single-word lookups (`openChat`, `WordWriter`, word detail, card pronunciation) loaded the whole library, including every audio blob, and the delete-all dialog loaded it just to count. | `word(id:)` and `wordCount()` on `WordRepository`. Test added. | `WordRepository.swift`, `RootView.swift`, `WordWriter.swift`, `WordDetailHost.swift`, `VocabularyCardPronunciation.swift`, `SettingsView.swift` |
| F13 | 40 saves ignored their errors; an import could report words imported that were never written. | `Persistence.save` (logs, returns Bool); import rolls back and throws `saveFailed`. | `Core/Storage/Persistence.swift`, all repositories, `VocabularyLibraryExporter.swift` |
| F16 | Words queued while there was no API key stayed failed after a key was added, until the person found Retry. Card sync, orphan cleanup and section names loaded every full word. | Saving a key requeues those items and starts a drain; `wordSummaries()` partial fetch for the library-wide jobs. Two tests added. | `AppEnvironment.swift`, `WordRepository.swift`, `WordQueueProcessorTests.swift`, `SwiftDataWordRepositoryTests.swift` |
| F14 | Huge factorials/exponents could tie up the on-device math engine until the app exits. | Refused up front (Gemini fallback answers). Two tests added. | `Features/Solve/Service/LocalMathEngine.swift`, `LocalMathSolverTests.swift` |
| F15 | `listModels` could loop on a repeated page token; an unencodable body was sent empty. | Token and page guard; body validated before sending. Two tests added. | `Core/AI/GeminiClient.swift`, `GeminiClientTests.swift` |
| F17 | A cancelled request was reported as a timeout (`ResilientAIClient`) or "unknown" (`URLError.cancelled`). | New `AIError.cancelled` (not retryable, never benches a key or model); all exhaustive switches, Arabic string, tests. | `AIError.swift`, `ErrorStrategy.swift`, `GeminiClient.swift`, `ResilientAIClient.swift`, `GeminiMathSolver.swift`, tests |
| F18 | Wolfram pod images were fetched from whatever host the reply named and the size cap was checked after the download. | Only `https` on `wolframalpha.com` hosts; the download stops as soon as it passes the cap. Fixtures moved to `www4b.wolframalpha.com`; two tests added. | `Features/Solve/Service/WolframSolver.swift`, `WolframSolverTests.swift` |
| F19 | Import trusted the file: huge strings or lists came in. Export wrote an empty `.json` if encoding failed. | Import clips with the validator's rules but never rejects (old exports still import); `encode` and `exportData` throw, Settings shows the failure; a save failure during import has its own message. | `ContentValidator.swift`, `VocabularyLibraryExporter.swift`, `WordRepository.swift`, `SettingsView.swift`, tests |
| F20 | A reply with a line of chatter before the code fence was not unwrapped; an absurdly large reply was decoded. | `CodeFence.extractJSON` (JSON that already starts with `{`/`[` is left alone); 24 MB cap. | `CodeFence.swift`, `GeminiClient.swift`, `GeminiClientTests.swift` |
| F21 | The math engine leaked a thread and a JavaScript context for each run that had to be abandoned. | After 3 abandoned runs the engine answers "unsupported" for the session (Gemini answers). Keychain `read()` trims like `save()`. | `LocalMathEngine.swift`, `KeychainStore.swift`, `LocalMathSolverTests.swift` |
| F22 | Bridge: a message was converted and re-serialised before its size was checked; a slow write reported "timeout" although it completed; a killed web-content process left a blank page. | Size first; writes run to completion and report their real outcome; the page is reloaded (at most twice). Tests added. | `PalabraBridge.swift`, `BridgeDispatcher.swift`, `ArtifactSandbox.swift`, `AppRendererView.swift`, tests |
| F23 | A word could be shown as saved, and its queue item deleted, although the write never reached the disk. | `WordRepository.flush()`; `WordWriter.commit` returns nil on failure; the queue keeps the item (retries, then failed); the preview sheet says so. Tests with an unsavable repository double. | `WordRepository.swift`, `WordWriter.swift`, `WordQueueProcessor.swift`, `WordPreviewSheet.swift`, tests |
| F24 | Pronunciation clips lived inside the word row, so every full fetch (library screen, export, capabilities) loaded every clip. | One file per word in Application Support (not backed up); old clips still play and move to files in batches at launch; deleting a word removes its file. The `pronunciationAudio` column stays (schema unchanged) and is empty after the move. | `PronunciationFileStore.swift`, `WordRepository.swift`, `PronunciationButton.swift`, `AppEnvironment.swift`, `RootView.swift`, tests |
| F25 | Repositories used their own `ModelContext` while views used the container's main context. | Everything shares `container.mainContext`. | `App/PalabraApp.swift` |
| F26 | Review due times were "now + n x 24 h": a card answered at 21:00 was not due at 08:00 the next day. | Review-phase cards are due at the start of a study day (04:00 local) `n` days on; learning steps stay minute-based; grade buttons show the interval ("1d"); the daily new-card limit uses the same day. Tests with a fixed calendar, including a clock change. | `SRSScheduler.swift`, `CardRepository.swift`, `ReviewViewModel.swift`, `StudyTypes.swift`, `SRSSchedulerTests.swift` |
| F27 | UI test failures never failed the build; the API key was visible to every unit test; no check for the AGENTS.md rules; historical docs cluttered searches. | The UI step fails the job (summaries still run); the key is given only to the live smoke test; `scripts/check-conventions.sh` runs first; tool versions are printed; `docs/superpowers` moved to `docs/archive/superpowers`; `reviewStats` fetches only dates; the detail page decodes once. | `.github/workflows/build-ipa.yml`, `scripts/check-conventions.sh`, `docs/` |

## Checked and fine

- API key goes only in the `x-goog-api-key` header; Keychain item is `WhenUnlockedThisDeviceOnly`; no secrets are committed.
- Arabic strings: 507 keys; the only apparent misses were false positives (`\u{2026}` escapes).
- Bridge grants are enforced in `CapabilityRegistry.call`, not by the page-visible `granted` list.
- `NavigationGate`, `createWebViewWith -> nil`, non-persistent store and the network block rules behave as documented.
- Logic coverage is broad: only SwiftUI views lack unit tests, and `GeminiClientTests` inspects request bodies.
