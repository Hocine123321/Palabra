# Code review: weaknesses and follow-ups

Review of `main` at `afb5bfb` (2026-10-19). Done by reading the code; **nothing was compiled or run**, so every fix below is
"compiled by eye" and needs a real CI run. Come back to this file to pick up the open items.

**Not read in depth:** `SettingsView`, the Spec renderer/validator internals, `ArtifactDraft*`, `CapabilityProviders` internals,
`ModelHealth`, `GeminiMathSolver` parsing, `WolframParser`, the design-system views, and the JS (`solver.js`, nerdamer).
Findings here come from the files that were read; absence of a finding is not a clean bill of health.

Status: **Fixed** = changed in the review pass (see "Fixed" for the files), **Open** = still to do.

---

## Open: fix next (highest value first)

### R1. Word rows are huge and are loaded whole, everywhere (Med-High, performance/memory)
- `Word.pronunciationAudio` (a WAV per word) sits inline in the main row next to `contentData`, `rawJSON`, `chatData`.
  Nothing uses `.externalStorage` or a partial fetch, so **every `allWords()` loads every audio blob**.
- `allWords()` is called on the main actor at launch and on each Study visit (`AppEnvironment.syncVocabularyCards`,
  `syncReviewNeeds`), in `requestOrganizationIfConfigured` (just to collect category names), in `RootView.openChat`
  and `WordWriter.commit` (to find one word by id), and by `updatePlacements` / `clearAllPlacements` / export.
- Fix: add `word(id:)` and a light `wordSummaries()` (id, spanish, translation, category) to `WordRepository`, and use them
  in those call sites. Move audio out of the row: a new `WordAudio` entity or a file cache in Application Support
  (adding a model is safe per AGENTS.md; changing `Word` is not, so do not flip `.externalStorage` without a tested migration).
  `FetchDescriptor.propertiesToFetch` may avoid loading blobs for the listing; verify on a device before relying on it.

### R2. Review due times are "now + n x 24 h", not calendar days (Med, UX)
- `SRSScheduler.graduate` sets `due = now + interval * 86_400`. A card answered at 21:00 is not due at 08:00 the next day, so
  someone who studies at varying times sees fewer cards than expected, and the new-card day starts at midnight
  (`Calendar.current.startOfDay`).
- Fix (design decision, changes `SRSSchedulerTests`): round review-phase dues to the start of the due day with a rollover
  hour (Anki uses 04:00); keep minute-level steps for learning cards.

### R3. Persistence failures are silent (Med)
- 187 `try?` in `Palabra/`, 40 of them `try? context.save()`. A failed save still reports success (`record`, `insert`,
  `importData`, `replaceContent` ...), so the UI shows a saved word or an imported count that is not on disk.
- Fix: one `Persistence.save(_:) -> Bool` helper that logs to `ResilienceCenter` ("Recent Problems") and make repositories
  return the result where callers can react (import count, `WordQueueProcessor` removing a queue item only after a real save).

### R4. UI test failures never fail CI (Med)
- `build-ipa.yml`: the UI step has `continue-on-error: true` and only posts a notice, so a broken screen is a green build.
- Fix: keep the IPA job independent but make the `tests` job fail on UI failures once the suite is stable, or at least fail on
  a drop in passed cases.

### R5. A stuck on-device math run cannot be stopped (Med)
- `LocalMathEngine` abandons a run after 8 s but the JavaScriptCore thread keeps spinning (`1000000!`, huge powers), costing CPU
  and battery until the app exits, and each timeout loads the large nerdamer bundle into a fresh context.
- Fix: refuse inputs that are known to explode (factorial / power size limits, length) in `MathInputNormalizer` before the engine
  runs; count timeouts and stop using the engine for the session after a few.

### R6. Two `ModelContext`s over one store (Med-Low)
- All repositories share one `ModelContext(container)` (`AppEnvironment.live`), while views use `container.mainContext` through
  `@Query` / `.modelContainer`. Saves propagate, but the two can briefly disagree, and `Card` / `Word` objects held by a view
  can be invalidated by a repository delete in the other context.
- Fix: build the repositories on `container.mainContext`.

### R7. Smaller sandbox/bridge hardening (Low-Med)
- `PalabraBridge`: the `__log` path runs before the size limit; the whole message is converted to `JSONValue` and re-serialised
  just to measure it. Cap `message.body` size first.
- `BridgeDispatcher.race`: on timeout the work is cancelled but a write that already started still completes, so the page sees
  "timeout" for something that happened. Make writes report their own outcome or run them to completion before replying.
- `AIUsageLimiter` forgets the oldest of 64 sessions, which resets that session's limits. Fine in practice; keep a floor.
- `webViewWebContentProcessDidTerminate` only logs; the artifact goes blank with no way back. Show "Reload".
- Defence in depth: serve the document through a `WKURLSchemeHandler` with a real `Content-Security-Policy` header instead of
  regex-inserting a `<meta>` (the comment case is fixed, other contexts such as a `<head>` inside a script string are not).

### R8. `GeminiClient` / `ResilientAIClient` small things (Low)
- `listModels` follows `nextPageToken` with no page cap (a repeated token loops forever).
- `request.httpBody = try? JSONSerialization...` silently sends no body if encoding fails.
- `URLError.cancelled` maps to `.unknown`; `ResilientAIClient` reports a cancelled task as `.timeout`. Add an explicit cancelled case.
- No response size limit; `stripCodeFences` only handles a fence at the very start.
- `secureConnectionFailed`, `internationalRoamingOff`, `callIsActive` are not treated as offline.

### R9. Import and export (Low-Med)
- `importData` does not run `ContentValidator`; a damaged file can bring over huge strings or a word with the wrong number of
  examples. (The blank-headword case is fixed.) Run the validator in a tolerant mode (clip, do not reject) so old exports keep importing.
- `VocabularyLibraryExporter.encode` returns empty `Data` if encoding fails, which exports an empty file named `.json`.

### R10. Wolfram images (Low)
- Image URLs from the response are downloaded without checking scheme or host, and `maxImageBytes` is checked after the whole
  download. Require `https` and a `wolframalpha.com` host; use a bytes-limited download.

### R11. Performance in views (Low-Med)
- `Word.content`, `chat` and `tags` decode JSON on every access; views that read them in `body` decode repeatedly on large libraries.
  Cache the decoded value (transient property) and invalidate it in the setter.
- `CardRepository.reviewStats` still loads every `ReviewLog` for the streak; fetch only the dates or keep a daily summary.
- `StudyHomeView` / `RootView.refreshDueBadge` call `counts` often; it is now cheap, but debounce on tab changes.

### R12. Queue and key behaviour (Low)
- A queue item marked `.failed` for a missing key stays failed after the key is added until the person taps Retry. Reset such
  items when a key is saved.
- `SwiftData...Repository.inMemory()` uses `try!` and ships in the app target (only tests/previews call it).
- Keychain: `read()` returns the stored value untrimmed (save trims, so harmless today).

### R13. Chat, for later (Low, no action now)
- There is no destructive write capability today (`words.add`, `words.place`, `review.flag`, `study.addCards`). If one is added,
  it must confirm even when "Ask Before Making Changes" is off, because stored content can carry prompt injection.

### R14. CI and repo hygiene (Low)
- Runner image, Xcode version and `brew install xcodegen` are unpinned and uncached (slow, and a moving target).
- No SwiftLint / swift-format.
- `docs/superpowers/` is historical (a 5,000-line plan); it is labelled as such, but it still shows up in searches.
- `GEMINI_API_KEY` is exposed to the whole unit-test step; only `LiveSmokeTests` needs it.

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

## Checked and fine

- API key goes only in the `x-goog-api-key` header; Keychain item is `WhenUnlockedThisDeviceOnly`; no secrets are committed.
- Arabic strings: 507 keys; the only apparent misses were false positives (`\u{2026}` escapes).
- Bridge grants are enforced in `CapabilityRegistry.call`, not by the page-visible `granted` list.
- `NavigationGate`, `createWebViewWith -> nil`, non-persistent store and the network block rules behave as documented.
- Logic coverage is broad: only SwiftUI views lack unit tests, and `GeminiClientTests` inspects request bodies.
