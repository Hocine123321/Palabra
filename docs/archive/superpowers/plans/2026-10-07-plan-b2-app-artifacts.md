# Plan B2: App Artifacts (sandboxed web view, bridge, `ai.generate`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The user can ask the AI for an interactive app ("a conversation practice from my words"); it is previewed in a sandboxed web view that can call the app's capabilities (read library, `ai.generate`, storage) after one plain-language approval, saved, updated, and fixed from its own logged errors.

**Architecture:** `kind = app` payload is one HTML file. `AppRendererView` hosts it in a locked-down `WKWebView` (non-persistent store, content rules blocking the network, CSP). The only way out is `window.palabra.call(name, args)`, a `WKScriptMessageHandlerWithReply` whose logic is a pure `BridgeDispatcher` over the existing `CapabilityRegistry`. The generator, prompts and lint gain the `app` kind; grants are stored on `Artifact.grantedData`.

**Tech Stack:** SwiftUI, WebKit (`WKWebView`, `WKContentRuleList`), SwiftData, XCTest, XCUITest, XcodeGen, GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-10-06-artifacts-design.md` (§5 `ai.generate`, §6, §7 app renderer, §8, §11–§13). Builds on plan B1 (`2026-10-06-plan-b1-artifacts-spec.md`, on `main`, CI green at `addc6ae`). Plan C (`review.*`) is next and needs nothing from this plan except that `write` capabilities are already prompted for.

## Global Constraints

- iOS 17.0; `SWIFT_VERSION 5.0`; `SWIFT_STRICT_CONCURRENCY targeted`; no third-party code, no CDNs (WebKit is a system framework).
- `Features/Artifacts` never imports `Word`, `Deck`, `Card`, `ReviewNeed`; `Core` never imports `Features`. `ai.generate` is registered in `App/CapabilityProviders.swift`.
- Sandbox (spec §7): `WKWebsiteDataStore.nonPersistent()`; a `WKContentRuleList` blocking all `http`/`https`/`ws`/`wss` loads, compiled before the first load; CSP meta `default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:`; navigation away from the document cancelled; `javaScriptCanOpenWindowsAutomatically = false`; `loadHTMLString(_, baseURL: nil)`.
- Bridge (spec §7): handler name `palabra`; main frame only; message ≤ 256 KB (262,144 bytes); per-call timeout 30 s (120 s for `ai.generate`); shim at document start exposes `palabra.call(name, args) -> Promise`, `palabra.granted`, `palabra.theme`, `palabra.locale` (`"en"|"ar"`), `palabra.dir`; reply is `{ok:true,value}` or `{ok:false,error:{code,message}}`; `window.onerror` and rejected calls go to the in-memory error log.
- `ai.generate` (spec §5): args `{prompt ≤ 8000 chars, schema?, temperature?}` → `{text}`; fixed app-side system instruction; limits per artifact per open session: 10 calls per rolling minute and 100 total → `rateLimited`; `AIError` → `failed(<AIError.userMessage>)`.
- Permissions (spec §6): `.local` auto-granted; app artifacts need approval for `.read`, `.write`, `.ai`; approval shown in the preview before first interaction; result stored in `Artifact.grantedData` on Save; on update only the delta is prompted; effective grant = requested ∩ granted + `.local`; the registry re-checks on every call.
- Lint (spec §8): reject `<script src=http…>`, `<link href=http…>`, `localStorage`, a payload without `<html`; app HTML ≤ 20 KB is the prompt's budget, stored payload ≤ 65,536 bytes is the hard cap. At most one automatic retry per generation (truncation or lint failure).
- UI text keyed by English in `ar.lproj/Localizable.strings`; AI/artifact strings `Text(verbatim:)`; no raw `withAnimation`; design-system rules from `AGENTS.md`.
- `MockAIClient` changes additive only. Commit messages end with the repo's `Co-Authored-By` / `Claude-Session` trailers. Compiled by eye only: push after each task's tests are written, check CI before the next push (`cancel-in-progress` cancels a running build).

## Verified repo facts (live clone at `addc6ae`)

- `ArtifactKind` already has `.app`; `ArtifactEnvelopeParser` already accepts `kind: "app"`; `GrantPolicy.needingApproval/effectiveGrant` already treat `.app` (reads need approval for apps).
- `ArtifactGenerator` has `allowedKinds` (default `[.spec]`); `build` rejects non-spec with `.kindNotAvailable`; `update` rejects `kind != .spec`; `ArtifactPrompts.systemInstruction` already switches the manual to all classes when `.app` is allowed.
- `ArtifactGenError` has six cases (`ai, truncated, malformedEnvelope, invalidSpec, kindNotAvailable, tooLargeToExtend`), switched exhaustively in `ArtifactGenerator.run` and `ArtifactPrompts.retryAddendum`, and its messages are asserted translated in `LocalizationTests`.
- `ArtifactSession(artifactID:dryRun:)` is a plain struct; `ArtifactRepository` is a `@MainActor` protocol with one implementation (`SwiftDataArtifactRepository`); `Artifact.grantedNames` get/set exists but nothing writes it yet.
- `CapabilityProviders.registry(words:artifacts:calendar:now:)` is built in `AppEnvironment.init` before `self` is complete; `MainActorBox` is private to that file.
- `StubAIClient.generateJSON` returns the spec envelope for schema-less calls whose system instruction contains `---PAYLOAD---`; `fallo` → rate limited; `CURRENT PAYLOAD:` → adds an "Updated" block.
- Detail/draft views render only specs today (`ArtifactDetailView` shows "Not supported in this version yet" for `.app`; `ArtifactDraftView` always decodes `ArtifactSpec`).

## Review Focus

1. Truncated or lint-failing app HTML → one retry, then an error; a truncated *update* of a big app → "too large to extend". Tests: Task 1.
2. Malformed / oversized / non-main-frame bridge message, unknown or ungranted capability → `{ok:false}`, never a crash, logged. Tests: Task 2.
3. `ai.generate` flood, prompt over 8000 chars, offline/AI failure, no API key. Tests: Task 2.
4. Artifact tries to reach the network or navigate away (`fetch`, `<a href>`, `window.open`). Tests: Task 3 pins the rule list, CSP and the navigation policy as pure values.
5. Update asks for a new capability; user denies it, then saves or restores. Tests: Task 4 (`GrantPolicy` delta, grant persistence, effective grant).

## File Structure

| File | Responsibility |
|---|---|
| `Features/Artifacts/AI/ArtifactHTMLLint.swift` | reject unusable app HTML |
| `Features/Artifacts/AI/{ArtifactEnvelope,ArtifactPrompts,ArtifactGenerator}.swift` (modify) | `app` kind: error case, prompt rules, build/validate |
| `Features/Artifacts/Domain/AIUsageLimiter.swift` | rolling-minute + total call limiter per session |
| `Features/Artifacts/App/BridgeDispatcher.swift` | pure message → reply, size/shape checks, timeout |
| `Features/Artifacts/App/ArtifactSandbox.swift` | rule list JSON, CSP, shim JS, `WKWebViewConfiguration` factory |
| `Features/Artifacts/App/PalabraBridge.swift` | `WKScriptMessageHandlerWithReply` adapter |
| `Features/Artifacts/App/ArtifactErrorLog.swift` | in-memory runtime error log |
| `Features/Artifacts/App/AppRendererView.swift` | `UIViewRepresentable` + coordinator |
| `Features/Artifacts/Library/ArtifactApprovalCard.swift` | plain-language approval card |
| `Features/Artifacts/Library/{ArtifactDraftModel,ArtifactDraftView,ArtifactDetailView}.swift` (modify) | render apps, approvals, Fix with AI |
| `Features/Artifacts/Storage/ArtifactRepository.swift` (modify) | `setGranted` |
| `App/CapabilityProviders.swift`, `App/AppEnvironment.swift` (modify) | `ai.generate`, `AIGateway` |
| Modified: `Core/AI/StubAIClient.swift`, `ar.lproj/Localizable.strings`, `LocalizationTests.swift`, `AGENTS.md`, `docs/features/artifacts.md` | stub app envelope, strings, docs |

Tests mirror under `PalabraTests/Artifacts/`; UI test `PalabraUITests/ArtifactsUITests.swift` (extend).

---

### Task 1: HTML lint and the `app` kind in the generator

**Files:** Create `AI/ArtifactHTMLLint.swift`; Modify `AI/ArtifactEnvelope.swift`, `AI/ArtifactPrompts.swift`, `AI/ArtifactGenerator.swift`; Test `PalabraTests/Artifacts/{ArtifactHTMLLintTests,ArtifactGeneratorTests}.swift`, `PalabraTests/App/LocalizationTests.swift`.

**Interfaces:**
- Consumes: `ArtifactEnvelopeParser`, `CodeFence`, `CapabilityRegistry`, `ArtifactLimits.maxPayloadBytes`.
- Produces:
  - `enum ArtifactHTMLLint { static func check(_ html: String) -> Result<String, ArtifactHTMLLintError> }` (returns the trimmed HTML); `enum ArtifactHTMLLintError: Error, Equatable { case missingHTMLTag, externalResource(String), localStorage, tooLarge }` with `var detail: String`.
  - `ArtifactGenError.invalidApp(String)` (retryable; `userMessage` "The AI returned an app that couldn't be run. Try again or rephrase.").
  - `ArtifactGenerator` with `allowedKinds` containing `.app` accepts `kind:"app"` envelopes; the draft's `requests` are the envelope's names filtered to registered capabilities, sorted, unique; `update` accepts any kind in `allowedKinds`.
  - `ArtifactPrompts.systemInstruction` gains, when `.app` is allowed: the app rules (single file; no external URLs; `storage.get/set/remove` instead of `localStorage`; `palabra.call(name, args)` returns a Promise resolving to the value and rejecting with `{code,message}`; handle `ok:false`; theme CSS variables `--ink --ink-secondary --surface --accent --error --background`; honour `palabra.locale` / `palabra.dir`; HTML ≤ 20 KB), an app output example, and "choose kind app only when the person asked for something interactive".
  - `ArtifactPrompts.retryAddendum(for: .invalidApp(detail))`.

- [ ] **Step 1: Write failing tests.** `ArtifactHTMLLintTests`: `testAcceptsMinimalDocument` (`<html><body>x</body></html>` → `.success`, trimmed); `testRejectsMissingHTMLTag`; `testRejectsExternalScript` (`<script src="https://x/y.js">` and `src=http://`) → `.externalResource`; `testRejectsExternalLink` (`<link href='https://…'>`); `testRejectsProtocolRelativeSrc` (`src="//cdn.x/y.js"`); `testRejectsLocalStorage`; `testAllowsDataURIImages`; `testRejectsOver65536Bytes` → `.tooLarge`; `testIsCaseInsensitiveOnTags` (`<HTML>`, `<SCRIPT SRC=HTTP://…>`). `ArtifactGeneratorTests` (new cases, generator built with `allowedKinds: [.spec, .app]`): `testAppEnvelopeBuildsAppDraft` (kind `.app`, payload bytes equal the HTML, requests filtered/sorted: `["storage.get","library.words","nope","library.words"]` → `["library.words","storage.get"]`); `testAppWithoutHTMLTagIsInvalidAndRetriedOnce` (second call's prompt contains `COULD NOT BE USED`); `testAppUpdateSendsCurrentHTMLAndKeepsTitle`; `testAppTruncatedUpdateIsTooLargeToExtend`; `testSystemInstructionIncludesAppRulesOnlyWhenAppAllowed` (contains `palabra.call` and `ai.generate` with `.app`, neither without; `ai.generate` registered as `.ai`); `testSpecOnlyGeneratorStillRejectsAppKind` (the existing test keeps passing). `LocalizationTests.testArabicStringsCoverArtifactErrorMessages` adds `.invalidApp("")`.
- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/Features/Artifacts/AI/ArtifactHTMLLint.swift 2>&1` — Expected: no such file.
- [ ] **Step 3: Implement** lint (regex on lower-cased text for `<html`, `src|href` attributes whose value starts with `http:`, `https:`, `//`; `localstorage`; byte cap), the error case in `ArtifactGenError` and every `switch` over it, the prompt additions, and the `app` branch of `ArtifactGenerator.build` (lint → `.invalidApp(detail)`; payload is the lint-trimmed HTML as UTF-8; envelope with `kind == .app` while `.app` not allowed → `.kindNotAvailable`). Add the Arabic message for `.invalidApp` to `Localizable.strings`.
- [ ] **Step 4: Commit** `feat(artifacts): app kind in the generator, with HTML lint`.

---

### Task 2: Bridge dispatcher, `ai.generate`, rate limiter, grant storage

**Files:** Create `Domain/AIUsageLimiter.swift`, `App/BridgeDispatcher.swift`; Modify `Storage/ArtifactRepository.swift`, `App/CapabilityProviders.swift`, `App/AppEnvironment.swift`; Test `PalabraTests/Artifacts/{AIUsageLimiterTests,BridgeDispatcherTests,AIGenerateCapabilityTests,GrantStorageTests}.swift`.

**Interfaces:**
- Consumes: `CapabilityRegistry.call`, `ArtifactSession`, `JSONValue`, `AIClient.generateJSON`, `AppEnvironment.apiKey/selectedModel/ai`.
- Produces:
  - `ArtifactSession` gains `var sessionID: UUID = UUID()` (memberwise init keeps working; views that need limits keep one session in `@State`).
  - `final class AIUsageLimiter: @unchecked Sendable { init(perMinute: Int = 10, total: Int = 100, now: @escaping @Sendable () -> Date = Date.init); func allow(sessionID: UUID) -> Bool; func end(sessionID: UUID) }` — thread-safe; rolling 60-second window; at most 64 live sessions tracked (oldest dropped).
  - `final class AIGateway: @unchecked Sendable { var run: (@Sendable (_ prompt: String, _ schema: JSONValue?, _ temperature: Double) async -> Result<String, AIError>)? }`.
  - `CapabilityProviders.registry(..., aiGateway: AIGateway = AIGateway(), aiLimiter: AIUsageLimiter = AIUsageLimiter())` adds `ai.generate` (`.ai`): prompt must be a non-empty string ≤ 8000 chars else `badArgs`; `temperature` clamped 0…2 (default 0.7); limiter denied → `rateLimited`; `gateway.run == nil` → `failed("AI is not available")`; `.failure(AIError)` → `failed(error.userMessage)`; success → `{text}`.
  - `AppEnvironment.aiGateway: AIGateway` wired after init: `run` reads `apiKey` (`nil` → `.missingAPIKey`) and `selectedModel` (`nil` → `.noModelSelected`) on the main actor and calls `ai.generateJSON(prompt:systemInstruction: <fixed Spanish-learning instruction>, schema: schema?.foundationObject, apiKey:, model:, temperature:)`.
  - `enum BridgeLimits { static let maxMessageBytes = 262_144; static let defaultTimeout: TimeInterval = 30; static let aiTimeout: TimeInterval = 120 }`
  - `enum BridgeReply: Equatable { case ok(JSONValue), error(code: String, message: String); var json: JSONValue { get } }` where `json` is `{ok:true,value}` or `{ok:false,error:{code,message}}`; codes: `unknown`, `notGranted`, `badArgs`, `failed`, `rateLimited`, `badMessage`, `timeout`.
  - `struct BridgeDispatcher { let registry: CapabilityRegistry; let session: ArtifactSession; let granted: @Sendable () -> Set<String>; var timeout: @Sendable (String) -> TimeInterval; var onError: @Sendable (String) -> Void; init(registry:session:granted:onError:); func handle(body: JSONValue, byteCount: Int, isMainFrame: Bool) async -> BridgeReply }` — body must be `{name: String, args: object|null}`; non-main-frame, `byteCount > 262_144` or wrong shape → `.error("badMessage", …)`; otherwise `registry.call` raced against the timeout; each failure calls `onError` with a one-line text.
  - `ArtifactRepository.setGranted(artifactID: UUID, names: [String])` (sorted, unique; no-op for unknown id) and `SwiftDataArtifactRepository` implementation.

- [ ] **Step 1: Write failing tests.** `AIUsageLimiterTests`: 10 calls pass then the 11th is denied; after the injected clock advances 61 s one passes; the 101st total is denied even across minutes; two session ids are independent; `end` forgets a session. `BridgeDispatcherTests` (registry from `makeCapability`): `testReadSucceeds` (`.ok(value)` and `json` shape); `testUnknownCapability` (`unknown`); `testUngrantedCapability` (`notGranted`); `testBadShapeIsBadMessage` (array body, missing name, name not a string); `testOversizedMessage` (`byteCount: 262_145` → `badMessage`, handler never called); `testNonMainFrameRejected`; `testNilArgsTreatedAsEmptyObject`; `testTimeoutReturnsTimeoutReply` (handler sleeps, injected timeout 0.05 s); `testErrorsAreReportedToLog` (counter on `onError`); `testGrantIsReadOnEveryCall` (granted closure changes between calls); `testLocalNeedsNoGrant`. `AIGenerateCapabilityTests` (registry with a scripted `AIGateway.run` recording calls): `testReturnsText`; `testPromptTooLongIsBadArgs` (8001 chars) and exactly 8000 passes; `testEmptyPromptBadArgs`; `testTemperatureClamped` (recorded 2.0 for 9, 0.0 for -1, 0.7 default); `testRateLimitedAfterTen` (`.rateLimited` on the 11th, run called 10 times); `testAIErrorMapsToFailedWithGuidance` (`.offline` → `.failed(AIError.offline.userMessage)`); `testNoGatewayFailsCleanly`; `testNotGrantedWithoutApproval`; `testManualListsAIGenerate`; `testAIClassNeedsApprovalForApp` (`GrantPolicy.needingApproval(kind: .app, requested: ["ai.generate","storage.get"], registry:)` → only `ai.generate`; for `.spec` the same call → `ai.generate` still listed, because specs cannot be granted it — pin current behaviour). `GrantStorageTests` (`@MainActor`): `testSetGrantedRoundTrips`; `testSetGrantedSortsAndDedupes`; `testSetGrantedUnknownIDIsNoOp`; `testGrantSurvivesAddVersion`.
- [ ] **Step 2: Verify RED by eye.** Run: `grep -n "sessionID\|AIUsageLimiter" -r Palabra | head -3` — Expected: no output.
- [ ] **Step 3: Implement** in the order: limiter, `ArtifactSession.sessionID`, repository method, dispatcher (race with `withThrowingTaskGroup`, first finisher wins, cancel the other), gateway + provider, environment wiring. `JSONValue` → Foundation conversion helper `var foundationObject: Any` lives in `JSONValue.swift`.
- [ ] **Step 4: Commit** `feat(artifacts): bridge dispatcher, ai.generate and grant storage`.

---

### Task 3: Sandbox, shim and the web view

**Files:** Create `App/ArtifactSandbox.swift`, `App/PalabraBridge.swift`, `App/ArtifactErrorLog.swift`, `App/AppRendererView.swift`; Test `PalabraTests/Artifacts/{ArtifactSandboxTests,ArtifactErrorLogTests}.swift`.

**Interfaces:**
- Consumes: `BridgeDispatcher`, `BridgeLimits`, `Theme`, `SupportedLanguage`.
- Produces:
  - `enum ArtifactSandbox`: `static let csp: String` (exactly the constraint string above); `static let blockRulesJSON: String` (a JSON array with one rule `{"trigger":{"url-filter":"^(https?|wss?)://"},"action":{"type":"block"}}`); `static func shimScript(granted: [String], themeCSS: [String: String], locale: String, dir: String) -> String` (defines `window.palabra` with `call`, `granted`, `theme`, `locale`, `dir`; inserts the CSP `<meta>` into the document head; applies theme variables to `:root`; forwards `window.onerror`, `unhandledrejection` and rejected `call`s to `webkit.messageHandlers.palabra.postMessage({name:"__log", args:{message}})`); `static func isAllowedNavigation(_ url: URL?, isMainFrameInitialLoad: Bool) -> Bool` (only the initial `about:blank` document load is allowed); `@MainActor static func makeConfiguration(handler: WKScriptMessageHandlerWithReply, shim: String, rules: WKContentRuleList?) -> WKWebViewConfiguration` (non-persistent store, `javaScriptCanOpenWindowsAutomatically = false`, user script at document start for the main frame only, handler registered for `palabra` in `.page` world, rules added); `@MainActor static func compileRules() async -> WKContentRuleList?`.
  - `__log` is handled by the bridge itself (appends to the log, replies `ok(null)`), never by the registry.
  - `@MainActor @Observable final class ArtifactErrorLog { private(set) var entries: [String]; func append(_ text: String); func clear(); var summary: String }` — newest 20 kept, each entry capped at 300 chars, `summary` is the entries joined by newlines.
  - `final class PalabraBridge: NSObject, WKScriptMessageHandlerWithReply` — converts `message.body` (`Any`) to `JSONValue` via `JSONSerialization`, measures bytes, calls `dispatcher.handle`, replies with `reply.json.foundationObject`; every failure path still calls `replyHandler`.
  - `struct AppRendererView: UIViewRepresentable { init(html: String, registry: CapabilityRegistry, session: ArtifactSession, granted: Set<String>, log: ArtifactErrorLog, colorScheme: ColorScheme, language: SupportedLanguage) }` — compiles the rule list first (shows `ProgressView` until ready), loads `html` with `baseURL: nil`, never reloads on SwiftUI re-renders (`updateUIView` is a no-op; identity is controlled by `.id(...)` at the call site), cancels navigation via `WKNavigationDelegate.decidePolicyFor`, denies `window.open` (`createWebViewWith` returns `nil`), ends the limiter session on disappear. The web view is transparent over `Theme.background`.

- [ ] **Step 1: Write failing tests.** `ArtifactSandboxTests`: `testCSPIsExact`; `testBlockRulesAreValidJSONWithOneBlockRule` (decode with `JSONSerialization`, assert the url-filter and action); `testShimDefinesPalabraAPI` (contains `palabra`, `call`, `granted`, `theme`, `locale`, `dir`, the CSP, `onerror`, `unhandledrejection`); `testShimEmbedsGrantedAsJSONArray` (`["library.words","storage.get"]` appears verbatim and a name containing a quote is escaped, not breaking the script); `testShimEmbedsThemeVariables`; `testNavigationPolicyOnlyAllowsInitialBlankLoad` (`about:blank` main-frame initial → true; `https://x` → false; `data:` after load → false; `nil` → false); `testRulesCompileAndCompilationIsRepeatable` (`@MainActor`, awaits `ArtifactSandbox.compileRules()` twice, both non-nil). `ArtifactErrorLogTests`: keeps newest 20; caps entry length at 300; `summary` joins; `clear`.
- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/Features/Artifacts/App 2>&1` — Expected: no such directory.
- [ ] **Step 3: Implement.** Escape every interpolated value with `JSONValue.jsonString` (never string concatenation of raw names). `makeConfiguration` uses `WKUserScript(source:injectionTime: .atDocumentStart, forMainFrameOnly: true)`. Keep each file under ~150 lines; JS lives in one multi-line string in `ArtifactSandbox.swift`.
- [ ] **Step 4: Commit** `feat(artifacts): sandboxed web view and bridge`.

---

### Task 4: Approval, app rendering in the Artifacts screens, stub, UI test, docs

**Files:** Create `Library/ArtifactApprovalCard.swift`; Modify `Library/{ArtifactDraftModel,ArtifactDraftView,ArtifactDetailView}.swift`, `Core/AI/StubAIClient.swift`, `ar.lproj/Localizable.strings`, `PalabraTests/App/LocalizationTests.swift`, `PalabraUITests/ArtifactsUITests.swift`, `AGENTS.md`, `docs/features/artifacts.md`; Test `PalabraTests/Artifacts/{ArtifactApprovalTests,StubArtifactTests,ArtifactDraftModelTests}.swift`.

**Interfaces:**
- Consumes: Tasks 1–3, `GrantPolicy`, `ArtifactRepository.setGranted`, `ArtifactErrorLog`.
- Produces:
  - `struct ArtifactApproval { static func pending(kind: ArtifactKind, requested: [String], granted: Set<String>, registry: CapabilityRegistry) -> [Capability] }` — capabilities in `requested` that exist, are not auto-granted for `kind`, and are not in `granted` (sorted by name). `static func effective(kind:requested:granted:registry:) -> Set<String>` delegates to `GrantPolicy.effectiveGrant`.
  - `struct ArtifactApprovalCard: View { init(capabilities: [Capability], onAllow: () -> Void, onDeny: () -> Void) }` — heading "This artifact wants to", one row per capability: `Text(verbatim: capability.summary)` plus a class label ("Read your data", "Change your data", "Use your AI quota"); buttons `allowArtifactButton` ("Allow") and `denyArtifactButton` ("Not now").
  - `ArtifactDraftModel` gains `var approved: Set<String>`, `var decided: Bool`, `func allowPending()`, `func denyPending()`; `generate`/`refine` reset `decided` only when the new draft's pending set differs from the previous; `save()` calls `artifacts.setGranted(artifactID:names:)` with the union of the artifact's existing grants and `approved` (create → `approved`). The generator is built with `allowedKinds: [.spec, .app]`.
  - `ArtifactDraftView` preview: spec → unchanged; app → if pending is non-empty and not `decided`, show the approval card only; otherwise `AppRendererView(html:…, session: ArtifactSession(artifactID: nil, dryRun: true) held in @State, granted: effective, log:…)` with `.id(draft.payload hash + approved)`.
  - `ArtifactDetailView`: for `.app`, reads `grantedNames` and shows the approval card for the delta before the web view; Allow persists via `setGranted` (union); an "Errors" section (identifier `artifactErrors`) lists `log.entries` with button `fixWithAIButton` ("Fix with AI") that opens the update sheet with `initialRequest = "Fix these runtime errors:\n" + log.summary`; `ArtifactDraftView` gains `var initialRequest: String = ""`.
  - `StubAIClient`: schema-less artifact envelope whose prompt contains `practice app` and not `CURRENT PAYLOAD:` returns `{"kind":"app","title":"Stub app","requests":["library.words","storage.get"]}` + a minimal valid HTML (`<html><body><div id="out">stub app</div><script>palabra.call("library.words",{limit:5}).then(function(w){document.getElementById("out").textContent="words:"+w.length})</script></body></html>`); an update prompt carrying that HTML (contains `stub app`) returns the same app with the title text `Stub app updated` inserted. Existing spec behaviour unchanged.
  - New Arabic strings: `This artifact wants to`, `Allow`, `Not now`, `Read your data`, `Change your data`, `Use your AI quota`, `Errors`, `Fix with AI`, `The AI returned an app that couldn't be run. Try again or rephrase.`.

- [ ] **Step 1: Write failing tests.** `ArtifactApprovalTests`: `testPendingListsOnlyUngrantedNonAutoCapabilities` (app requesting `library.words`, `storage.get`, `ai.generate`, granted `["library.words"]` → `["ai.generate"]`); `testSpecNeverPendingForReads` (spec requesting `library.words` → `[]`); `testPendingIsDeltaOnUpdate`; `testEffectiveIsRequestedIntersectGrantedPlusLocal` (denied capability absent; `storage.get` present; unknown dropped); `testDeniedThenRestoredOldVersionKeepsOldGrants` (repository: create with grants `["library.words"]`, addVersion requesting more, restore → `grantedNames` unchanged). `StubArtifactTests`: `testStubAppEnvelopeParsesThroughGenerator` (generator `allowedKinds: [.spec,.app]`, request "build a practice app": kind `.app`, requests `["library.words","storage.get"]`, HTML passes the lint); `testStubAppUpdateChangesTitleText`; existing three tests still pass. `ArtifactDraftModelTests` (`@MainActor`, `AppEnvironment` test factory with `StubAIClient`, API key and model set as `NotesDeckModel`'s tests do): `testAppDraftNeedsApprovalThenSavesGrants` (generate "practice app" → phase `.preview`, pending `[library.words]`; `allowPending(); save()` → artifact `grantedNames == ["library.words"]`); `testDenyThenSaveStoresNoGrants`; `testUpdateGrantsAreUnioned`. `LocalizationTests.testArabicStringsHaveArtifactKeys` adds the nine new keys. UI test `testAppArtifactApprovalAndSave` in `ArtifactsUITests` (stub AI, `-UITestSeed 3`): open Artifacts → New → type "a practice app" → Generate → `allowArtifactButton` exists → tap → `app.webViews.firstMatch` exists → `saveArtifactButton` → `artifactRow` exists → open it → `app.webViews.firstMatch` exists and `allowArtifactButton` does not (grant persisted). No assertion reads text inside the web view.
- [ ] **Step 2: Verify RED by eye.** Run: `grep -n "practice app" Palabra/Core/AI/StubAIClient.swift` — Expected: no output.
- [ ] **Step 3: Implement** the card, model/view changes, stub branch, strings. The detail view keeps one `ArtifactErrorLog` and one `ArtifactSession` in `@State`; a spec artifact path is untouched.
- [ ] **Step 4: Document.** `docs/features/artifacts.md`: app kind, sandbox rules, bridge protocol and error codes, `ai.generate` limits, approval flow, Fix with AI, "JS behaviour inside the web view is not covered by CI". `AGENTS.md`: layout entry `App/` under Artifacts; rules: bridge dispatch stays pure; the shim is the only JS the app injects; never loosen CSP or the rule list without updating `ArtifactSandboxTests`; every app capability needs a manual summary because it is shown to the user; update the "Spec artifacts never prompt" bullet to say app artifacts prompt via `ArtifactApprovalCard`.
- [ ] **Step 5: Verify by eye.** Run: `grep -rn "withAnimation\|\.animation(" Palabra/Features/Artifacts` — Expected: no output; `grep -rnw "Word\|Deck\|Card" Palabra/Features/Artifacts` — Expected: only the JSON example line in `SpecBlock.swift`; `grep -rn "http" Palabra/Features/Artifacts/App/ArtifactSandbox.swift` — Expected: only the block-rule url-filter and the CSP-related comments.
- [ ] **Step 6: Commit** `feat(artifacts): app artifacts with approval and Fix with AI`.

---

## Self-review

- **Spec coverage:** §5 `ai.generate` (Task 2); §6 permissions incl. delta and denial (Tasks 2, 4); §7 app renderer sandbox/bridge/shim/dispatch-as-pure-function (Tasks 2, 3); §8 app prompts, lint, retry budget, preview with dry run, Fix with AI, update with truncation limit (Tasks 1, 4); §11 error rows for ungranted/bad args/oversized/rate limit (Task 2); §12 bridge/lint/generator/provider tests and the isolated app UI fixture (Tasks 1–4); §13 items 3, 4, 6, 8, 9 (Review Focus + tests). Items 1, 2, 5, 7 belong to plan C / B1 (RTL: the shim passes `locale`/`dir`, tested in Task 3).
- **Deliberate deviations:** the UI test does not read text inside the web view (spec says it may be flaky); `AIGateway` is a small seam because `AppEnvironment.init` cannot hand `self` to the registry; `ArtifactSession.sessionID` is added so "per open session" limits do not reset on SwiftUI re-renders.
- **Type consistency:** `ArtifactGenError.invalidApp(String)` is added in Task 1 and used in Tasks 1 and 4; `ArtifactSession` init stays source-compatible; `BridgeReply.json`, `BridgeLimits`, `AIUsageLimiter.allow(sessionID:)` and `ArtifactErrorLog.summary` are defined once (Tasks 2–3) and only consumed later.
- **Proportion:** four tasks; each ends in a CI-checkable deliverable and the plan states signatures, values and test names rather than bodies.
