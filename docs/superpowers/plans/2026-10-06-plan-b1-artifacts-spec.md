# Plan B1: Artifacts Platform with Spec Artifacts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The user asks the AI for a table, chart, roadmap or checklist; it is previewed, saved as an artifact, reopened later, updated, and rolled back — and tables/charts can bind live to library data.

**Architecture:** A capability registry (the single source of truth for what an artifact may call, and for the AI's manual) sits under a declarative `spec` renderer. Artifacts persist as versioned SwiftData records. `CapabilityProviders` in `App/` is the only code that sees both `Word` and artifacts. Generation uses one `generateJSON(schema: nil)` call with a delimited envelope.

**Tech Stack:** SwiftUI, SwiftData, Swift Charts (system framework), XCTest, XCUITest, XcodeGen, GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-10-06-artifacts-design.md` (§3–§8, §10–§14). This is plan B1 of A, B1, B2, C, D+.

**Precondition:** Plan A (`2026-10-06-plan-a-spanish-hub.md`) is on `main` with green CI. As of writing, `origin/main` is still `81dc10f` (Plan A is only in the delivered zip and local commit `f991ba4`). This plan edits `SpanishHomeView`, `Router.Destination` and `UITestHelpers.swift` from Plan A; do not start Task 1 until Plan A is pushed.

## Global Constraints

- iOS 17.0; `SWIFT_VERSION 5.0`; `SWIFT_STRICT_CONCURRENCY targeted`; no third-party dependencies (Swift Charts is a system framework).
- `Features/Artifacts` never imports `Word`, `Deck`, `Card`, `ReviewNeed`; `Core` never imports `Features`. `App/CapabilityProviders.swift` is the only file that sees both `WordRepository` and `ArtifactRepository`.
- Persisted names are append-only: `Artifact`, `ArtifactVersion`, `ArtifactStateEntry` and their stored properties; `ArtifactKind` raw values `"spec"`, `"app"`.
- Limits (verbatim from the spec): stored payload ≤ 64 KB (65 536 bytes); newest 20 versions per artifact; artifact state ≤ 256 KB total (sum of value bytes), key ≤ 64 chars; capability args ≤ 64 KB encoded; spec ≤ 60 blocks total, depth ≤ 4, table ≤ 20 columns × 200 rows, chart ≤ 500 points; `library.words` limit 1…500 (default 100); `stats.wordsPerDay` days 1…365; `stats.wordsPerWeek` weeks 1…104.
- String caps in `SpecValidator` (truncate, don't reject): heading 120, text 2000, list item 300 (≤ 100 items), table cell 200, chart title 80, chart label 40, stat label 40, stat value 60, checklist item 200 (≤ 50), roadmap step title 120 / detail 300 (≤ 30 steps), section title 120.
- Spec artifacts request only `.read` (for `bind`) and `.local` capabilities; both are auto-granted, so B1 has no approval sheet. Until plan B2, the generation prompt allows only `kind: spec`.
- Wire format: header JSON line `{"kind","title","requests"}`, then `---PAYLOAD---`, payload, `---END---`. A missing `---END---` is `.truncated`. At most one automatic retry per generation, for truncation or a `SpecValidator` failure (the spec kind's "lint failure").
- AI strings render with `Text(verbatim:)`; `ForEach` uses enumerated offsets; AI output is capped in `SpecValidator`.
- Design system: `.creamScreen()`/`themedSection()`, `GlassSurface`/`.glassCard()`, `.buttonStyle(.primary)`, `Theme.Radius.*`, `Theme.Font.*`, no `.tint`, no raw `withAnimation`.
- Localization keyed by English text in `ar.lproj/Localizable.strings`; UI tests find elements by identifier or English text.
- `MockAIClient` changes are additive only (no protocol change). Commit messages end with the repo's `Co-Authored-By` / `Claude-Session` trailers. Compiled by eye only: every task needs a real CI run, and Tasks 1–7 land in one push.

## Verified repo facts (re-read from the live clone)

- `Word` stored properties: `id`, `key`, `spanish`, `searchKey`, `contentData`, `rawJSON`, `translation`, `partOfSpeech`, `createdAt`, `updatedAt`, `chatData`, `pronunciationAudio`, `category`, `tagsData`; computed `tags`, `content`, `chat`. Init: `Word(spanish:key:searchKey:content:rawJSON:createdAt:)`.
- `WordRepository.insert(...)` has no `createdAt` parameter, so tests that need controlled dates insert `Word(...)` directly into a `ModelContext` and save.
- `AppEnvironment.init` takes `cardRepository: CardRepository? = nil` defaulting to `SwiftDataCardRepository.inMemory()`; `artifactRepository` follows the same pattern.
- `PalabraApp` builds `Schema([Word.self, WordQueueItem.self, Deck.self, Card.self, ReviewLog.self])` and deletes entities in the `-UITestReset` block.
- `StubAIClient.generateJSON` branches on `schema?["properties"]["cards"]` for Study and returns `"{}"` otherwise; artifact calls pass `schema: nil`, so they do not collide.
- `NotesDeckModel.run` is the pattern for key/model resolution and one `repairMissingModel()` retry.

## Review Focus

1. AI returns unknown block types, an empty `blocks`, or an invalid bind → dropped / `.empty`, never a crash. Tests: Task 3.
2. A bound capability fails, is ungranted, or the library is empty → inline "Couldn't load data" or an empty table. Tests: Task 6.
3. Truncated output → one retry then an error; a truncated update → "too large to extend". Tests: Task 5.
4. Payload > 64 KB, the 21st version, state overflow. Tests: Task 2.
5. Identical strings in lists/tables (AI strings must never be `ForEach` identity). Pinned by the stub fixture (two identical list items) in the Task 7 UI test.

## File Structure

| File | Responsibility |
|---|---|
| `Features/Artifacts/Domain/JSONValue.swift` | Codable JSON value |
| `Features/Artifacts/Domain/ArtifactKind.swift` | `ArtifactKind` |
| `Features/Artifacts/Domain/Capability.swift` | `Capability`, `CapabilityClass`, `CapabilityError`, `ArtifactSession` |
| `Features/Artifacts/Domain/CapabilityRegistry.swift` | dispatch + `manual` |
| `Features/Artifacts/Domain/GrantPolicy.swift` | who needs approval |
| `Features/Artifacts/Storage/ArtifactModels.swift`, `ArtifactRepository.swift` | SwiftData entities + repository |
| `Features/Artifacts/Spec/SpecBlock.swift`, `SpecValidator.swift` | block model, sanitizer |
| `Features/Artifacts/Spec/SpecBindLoader.swift`, `SpecStateStore.swift` | live data, tick state |
| `Features/Artifacts/Spec/SpecRenderer.swift`, `SpecTableView.swift`, `SpecChartView.swift`, `SpecChecklistViews.swift` | SwiftUI renderer |
| `Features/Artifacts/AI/ArtifactEnvelope.swift`, `ArtifactPrompts.swift`, `ArtifactGenerator.swift` | generation |
| `Features/Artifacts/Library/ArtifactsListView.swift`, `ArtifactDraftModel.swift`, `ArtifactDraftView.swift`, `ArtifactDetailView.swift` | Artifacts page |
| `App/CapabilityProviders.swift` | library/stats/storage capabilities |
| Modified: `PalabraApp.swift`, `AppEnvironment.swift`, `Router.swift`, `RootView.swift`, `SpanishHomeView.swift`, `StubAIClient.swift`, `AGENTS.md`, `ar.lproj/Localizable.strings`, `MockAIClient.swift`, `UITestHelpers.swift` | wiring |

Tests mirror under `PalabraTests/Artifacts/`; UI test `PalabraUITests/ArtifactsUITests.swift`.

---

### Task 1: JSON value, capabilities, registry, grant policy

**Files:** Create the five `Domain/` files above; Test: `PalabraTests/Artifacts/{JSONValueTests,CapabilityRegistryTests,GrantPolicyTests}.swift`.

**Interfaces:**
- Produces:
  - `enum JSONValue: Codable, Equatable, Sendable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }` with `subscript(key: String) -> JSONValue?`, `stringValue/intValue/doubleValue/boolValue/arrayValue/objectValue` optionals (`intValue` only for integral numbers), `static func parse(_ text: String) -> JSONValue?`, `var jsonString: String`.
  - `enum ArtifactKind: String, Codable, Sendable { case spec, app }`
  - `enum CapabilityClass: Sendable { case read, write, ai, local }`; `struct ArtifactSession: Sendable { let artifactID: UUID?; let dryRun: Bool }`; `enum CapabilityError: Error, Equatable { case unknown, notGranted, badArgs(String), failed(String), rateLimited }`
  - `struct Capability: Sendable { name, kind, summary, argsSchema: JSONValue (object: field → human description), returnsSummary, dryRunValue: JSONValue?, handler: @Sendable (JSONValue, ArtifactSession) async -> Result<JSONValue, CapabilityError> }`
  - `struct CapabilityRegistry: Sendable { init(_ capabilities: [Capability]); var all: [Capability] (sorted by name); func capability(named:) -> Capability?; func call(name: String, args: JSONValue, session: ArtifactSession, granted: Set<String>) async -> Result<JSONValue, CapabilityError>; func manual(including: Set<CapabilityClass> = [.read, .write, .ai, .local]) -> String }`. Later duplicates of a name replace earlier ones.
  - `enum GrantPolicy { static func autoGranted(kind: ArtifactKind, capability: Capability) -> Bool; static func needingApproval(kind: ArtifactKind, requested: [String], registry: CapabilityRegistry) -> [Capability]; static func effectiveGrant(kind: ArtifactKind, requested: [String], granted: Set<String>, registry: CapabilityRegistry) -> Set<String> }` — `autoGranted` = `.local` always, or `.read` when `kind == .spec`.

- [ ] **Step 1: Write failing tests.** Assertions:

```swift
// JSONValueTests
func testRoundTrip() { let v = JSONValue.parse(#"{"a":[1,"x",null,true],"b":{"c":2.5}}"#)!; XCTAssertEqual(JSONValue.parse(v.jsonString), v) }
func testIntValueOnlyForIntegral() { XCTAssertEqual(JSONValue.number(3).intValue, 3); XCTAssertNil(JSONValue.number(3.5).intValue) }
// CapabilityRegistryTests (handlers record invocation in a locked box)
func testUnknownName() async { /* call("nope") */ XCTAssertEqual(r, .failure(.unknown)) }
func testUngrantedReadIsNotGranted() async { XCTAssertEqual(r, .failure(.notGranted)) }
func testLocalIsAlwaysGranted() async { /* granted: [] */ XCTAssertEqual(r, .success(.object([:]))) }
func testOversizedArgsAreBadArgs() async { /* string of 65_537 bytes */ guard case .failure(.badArgs) = r else { return XCTFail() } }
func testDryRunWriteReturnsDryRunValueWithoutRunningHandler() async { XCTAssertEqual(r, .success(.string("ok"))); XCTAssertFalse(box.called) }
func testDryRunStillRunsReads() async { XCTAssertTrue(box.called) }
func testManualListsEveryCapabilityAndHonoursClasses() { XCTAssertTrue(all.contains("library.words")); XCTAssertFalse(readOnly.contains("review.flag")) }
// GrantPolicyTests: spec: read auto, write/ai not; app: read needs approval, local auto; effectiveGrant = requested ∩ (granted ∪ auto), unknown names dropped
```

- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/Features/Artifacts 2>&1` — Expected: "No such file or directory".
- [ ] **Step 3: Implement the five files** to the Interfaces block. `call` order: unknown → not granted (`.local` exempt) → args size (`jsonString.utf8.count > 65_536` → `badArgs`) → `session.dryRun && kind == .write` returns `dryRunValue ?? .object([:])` without invoking → handler. `manual` renders one block per capability: `- <name> (<class>): <summary>` / `  args: <argsSchema json>` / `  returns: <returnsSummary>`.
- [ ] **Step 4: Verify by eye.** Run: `grep -rn "import SwiftData\|Word\b" Palabra/Features/Artifacts/Domain` — Expected: no output.
- [ ] **Step 5: Commit** `feat(artifacts): JSON value, capability registry and grant policy`.

---

### Task 2: Storage models, repository, environment wiring

**Files:** Create `Storage/ArtifactModels.swift`, `Storage/ArtifactRepository.swift`; Modify `App/PalabraApp.swift`, `App/AppEnvironment.swift`, `AGENTS.md`; Test `PalabraTests/Artifacts/ArtifactRepositoryTests.swift`.

**Interfaces:**
- Consumes: `ArtifactKind`.
- Produces:
  - `@Model Artifact` (`@Attribute(.unique) id`, `title`, `kindRaw`, `currentVersion: Int`, `grantedData: Data`, `createdAt`, `updatedAt`; computed `kind`, `grantedNames: [String]`), `@Model ArtifactVersion` (`id`, `artifactID`, `number`, `payload: Data`, `requestedData: Data`, `prompt`, `createdAt`; computed `requestedNames`), `@Model ArtifactStateEntry` (`artifactID`, `key`, `valueData`, `updatedAt`).
  - `enum ArtifactLimits { static let maxPayloadBytes = 65_536, maxVersions = 20, maxStateBytes = 262_144, maxStateKeyLength = 64 }`; `enum ArtifactStorageError: Error, Equatable { case payloadTooLarge, storageFull, keyTooLong, notFound }`
  - `@MainActor protocol ArtifactRepository` with: `artifacts() -> [Artifact]` (newest `updatedAt` first); `artifact(id:) -> Artifact?`; `versions(artifactID:) -> [ArtifactVersion]` (newest first); `create(title:kind:payload:requested:prompt:now:) -> Result<Artifact, ArtifactStorageError>`; `addVersion(artifactID:payload:requested:prompt:now:) -> Result<ArtifactVersion, ArtifactStorageError>` (bumps `currentVersion`, prunes to 20, touches `updatedAt`); `restore(artifactID:versionNumber:now:) -> Result<ArtifactVersion, ArtifactStorageError>` (copies that payload/requested into a new version with prompt `"Restored version N"`); `delete(id:)` (artifact + versions + state); `stateValue(artifactID:key:) -> Data?`; `setStateValue(artifactID:key:value:) -> Result<Void, ArtifactStorageError>`; `removeStateValue(artifactID:key:)`.
  - `SwiftDataArtifactRepository(context:retaining:)` and `static func inMemory()` (as `SwiftDataCardRepository`).
  - `AppEnvironment.artifacts: ArtifactRepository` (init param `artifactRepository: ArtifactRepository? = nil`, default `inMemory()`).

- [ ] **Step 1: Write failing tests** (in-memory container of the three models):

```swift
func testCreateStartsAtVersionOne() { XCTAssertEqual(artifact.currentVersion, 1); XCTAssertEqual(repo.versions(artifactID: id).count, 1) }
func testAddVersionBumpsAndTouches()
func testPrunesToNewest20() { /* 21 versions */ XCTAssertEqual(vs.count, 20); XCTAssertEqual(vs.last?.number, 2); XCTAssertEqual(vs.first?.number, 21) }
func testRestoreCopiesPayloadIntoNewVersion() { XCTAssertEqual(v.number, 3); XCTAssertEqual(v.payload, original); XCTAssertEqual(v.prompt, "Restored version 1") }
func testPayloadOver64KBIsRejected() { XCTAssertEqual(result, .failure(.payloadTooLarge)) } // 65_537 bytes; 65_536 succeeds
func testDeleteRemovesVersionsAndState()
func testStateKeyTooLong() { /* 65 chars */ XCTAssertEqual(r, .failure(.keyTooLong)) }
func testStateOverflowAndReplaceDoesNotDoubleCount() { /* 262_144 total succeeds; +1 byte fails storageFull; overwriting a key swaps its size */ }
func testArtifactsNewestUpdatedFirst()
```

- [ ] **Step 2: Verify RED by eye.** Run: `grep -n "class Artifact" -r Palabra` — Expected: no output.
- [ ] **Step 3: Implement** the models, protocol and `SwiftDataArtifactRepository` (FetchDescriptors with `#Predicate`, one `context.save()` per mutation; `inMemory()` schema is the three artifact models).
- [ ] **Step 4: Wire.** Add the three models to the `Schema([...])` in `PalabraApp`; delete artifacts/versions/state in the `-UITestReset` block; pass `SwiftDataArtifactRepository(context: ModelContext(container))` in the UI-test environment and in `AppEnvironment.live`.
- [ ] **Step 5: Document.** In `AGENTS.md` "Names that must NOT be changed" add the three entities, their stored properties, and the `ArtifactKind` raw values (append-only).
- [ ] **Step 6: Commit** `feat(artifacts): versioned artifact storage`.

---

### Task 3: Spec blocks and validator

**Files:** Create `Spec/SpecBlock.swift`, `Spec/SpecValidator.swift`; Test `PalabraTests/Artifacts/SpecValidatorTests.swift`.

**Interfaces:**
- Consumes: `JSONValue`, `CapabilityRegistry`, `Capability.kind`.
- Produces:
  - `struct ArtifactSpec: Codable, Equatable, Sendable { var blocks: [SpecBlock] }`; `indirect enum SpecBlock: Codable, Equatable, Sendable` decoding by the `type` key. Unknown or undecodable blocks (also nested `children`) are **dropped**, not fatal.
  - Wire shapes (the prompt, the stub and tests all use these):

```
{"type":"heading","level":1,"text":"…"}   {"type":"text","text":"…"}   {"type":"list","ordered":false,"items":["…"]}
{"type":"table","columns":[{"title":"Day","field":null}],"rows":[["Lunes"]]}  |  …"bind":{"capability":"library.words","args":{"limit":10}} with columns[{title,field}]
{"type":"chart","style":"bar"|"line","title":"…","labels":["…"],"series":[{"name":"…","values":[1,2]}]}  |  …"bind":{…},"labelField":"day","valueField":"count"
{"type":"stats","tiles":[{"label":"…","value":"…"}]}   {"type":"checklist","id":"c1","items":["…"]}
{"type":"roadmap","id":"r1","steps":[{"title":"…","detail":"…"}]}   {"type":"columns","children":[…]}   {"type":"section","title":"…","children":[…]}
```

  - `static SpecBlock.catalog: String` — the human text of the list above, for the prompt.
  - `struct SpecBind: Codable, Equatable, Sendable { capability: String; args: JSONValue }`; `struct ValidatedSpec: Equatable { var spec: ArtifactSpec; var requests: [String] }`; `enum SpecValidationError: Error, Equatable { case empty, malformed(String) }`
  - `enum SpecValidator { static func decode(_ payload: String) -> Result<ArtifactSpec, SpecValidationError> (strips code fences); static func validate(_ spec: ArtifactSpec, requests: [String], registry: CapabilityRegistry) -> Result<ValidatedSpec, SpecValidationError> }`. `validate` truncates strings/arrays to the Global Constraints caps, enforces 60 blocks / depth 4 by dropping the excess, drops a block whose `bind.capability` is unknown or not `.read`, makes `checklist`/`roadmap` ids unique (`c1`, `c1-2`), and returns `requests` = sorted unique (manifest names that exist and are `.read`/`.local`) ∪ bind capabilities. No blocks left → `.empty`.

- [ ] **Step 1: Write failing tests:** `testDecodesEveryBlockType`; `testUnknownBlockTypeIsDropped`; `testNestedUnknownChildDropped`; `testAllBlocksUnknownIsEmpty` (`.failure(.empty)`); `testBlockCountCappedAt60` (61 text blocks → 60); `testDepthCappedAt4`; `testTableCappedAt20x200`; `testStringCaps` (text 2001 chars → 2000); `testBindToWriteCapabilityDropsBlock`; `testBindToUnknownCapabilityDropsBlock`; `testRequestsFilteredAndUnionedWithBinds` (manifest `["review.flag","library.words","nope"]` with a registry whose `review.flag` is `.write` → `["library.words"]`); `testDuplicateChecklistIdsRenamed`; `testFencedPayloadDecodes`; `testMalformedJSON` (`.failure(.malformed)`).
- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/Features/Artifacts/Spec 2>&1` — Expected: no such directory.
- [ ] **Step 3: Implement** both files. Lossy array decoding via a private `LossyDecodable<T>` wrapper.
- [ ] **Step 4: Commit** `feat(artifacts): spec block model and validator`.

---

### Task 4: Capability providers (library, stats, storage)

**Files:** Create `App/CapabilityProviders.swift`; Test `PalabraTests/Artifacts/CapabilityProvidersTests.swift`.

**Interfaces:**
- Consumes: `WordRepository` (`allWords()`), `Word` fields (`id`, `key`, `spanish`, `translation`, `partOfSpeech`, `category`, `tags`, `createdAt`, `content`), `ArtifactRepository` state methods, `CapabilityRegistry`.
- Produces: `enum CapabilityProviders { @MainActor static func registry(words: WordRepository, artifacts: ArtifactRepository, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) -> CapabilityRegistry }` registering exactly: `library.words`, `library.word` (class `.read`), `stats.wordsPerDay`, `stats.wordsPerWeek` (`.read`), `storage.get`, `storage.set`, `storage.remove` (`.local`). Behaviour per the spec §5 catalog:
  - `library.words {limit?, offset?, category?, tag?}` → newest first; items `{id, key, spanish, translation, partOfSpeech, category (string|null), tags, createdAt (ISO-8601 UTC)}`; no audio/chat keys; `category`/`tag` match case-insensitively.
  - `library.word {id}` or `{key}` → the item fields plus `content` (the word's `WordContent` JSON); neither given → `badArgs`; missing word → `failed("word not found")`.
  - `stats.wordsPerDay {days}` → `[{day:"yyyy-MM-dd", count}]` oldest first, ending today, zero days included, `calendar` time zone; `days` clamped to 1…365. `stats.wordsPerWeek {weeks}` → `[{weekStart:"yyyy-MM-dd", count}]`, weeks start on `calendar.firstWeekday`, clamped 1…104.
  - `storage.get {key}` → stored JSON or `null`; `storage.set {key, value}` → `{}`; `storage.remove {key}` → `{}`. When `session.dryRun` or `session.artifactID == nil` they use an in-memory scratch dictionary (keyed by artifact id or `"draft"`) instead of `ArtifactRepository`; otherwise `ArtifactRepository`, mapping `ArtifactStorageError` → `failed("storage full" | "key too long")`.

- [ ] **Step 1: Write failing tests** (in-memory containers; build words with `Word(spanish:key:searchKey:content:rawJSON:createdAt:)` inserted into a `ModelContext` and saved, then read through `SwiftDataWordRepository(context:)`; set placement via `updatePlacement`; fixed `Calendar` with a UTC time zone and a fixed `now`): `testLibraryWordsNewestFirstAndPaged`; `testLibraryWordsOmitsAudioAndChat` (no `pronunciationAudio`, `chatData` keys); `testLibraryWordsFiltersCategoryAndTag`; `testLibraryWordsEmptyLibrary` (`[]`); `testLibraryWordsLimitClamped` (0 → 1, 9999 → 500); `testLibraryWordByIdAndByKey`; `testLibraryWordNeitherArgIsBadArgs`; `testLibraryWordMissing`; `testWordsPerDayZeroFilledOldestFirst` (3 days, words on day 1 and 3 → counts `[1,0,2]`); `testWordsPerDayDayBoundary` (23:59 and 00:00 UTC land on different days); `testWordsPerDayClamped`; `testWordsPerWeekBuckets`; `testStorageRoundTripPersistent`; `testStorageDryRunDoesNotTouchRepository`; `testStorageOverflowMapsToFailed`; `testRegistryNamesAreUniqueAndComplete` (the seven names).
- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/App/CapabilityProviders.swift 2>&1` — Expected: no such file.
- [ ] **Step 3: Implement.** Repository access is `@MainActor`, so handlers hop with `await MainActor.run { … }`; fixed `DateFormatter` (`en_US_POSIX`, calendar time zone) for day strings.
- [ ] **Step 4: Commit** `feat(artifacts): library, stats and storage capabilities`.

---

### Task 5: Envelope, prompts, generator

**Files:** Create `AI/ArtifactEnvelope.swift`, `AI/ArtifactPrompts.swift`, `AI/ArtifactGenerator.swift`; Modify `PalabraTests/Support/MockAIClient.swift`; Test `PalabraTests/Artifacts/{ArtifactEnvelopeTests,ArtifactGeneratorTests}.swift`.

**Interfaces:**
- Consumes: `AIClient.generateJSON`, `CapabilityRegistry.manual(including:)`, `SpecValidator`, `SupportedLanguage.instructionName`.
- Produces:
  - `enum ArtifactGenError: Error, Equatable { case ai(AIError), truncated, malformedEnvelope(String), invalidSpec(String), kindNotAvailable, tooLargeToExtend }` with `var userMessage: String`.
  - `struct ArtifactEnvelope: Equatable { kind: ArtifactKind; title: String; requests: [String]; payload: String }`; `enum ArtifactEnvelopeParser { static func parse(_ text: String) -> Result<ArtifactEnvelope, ArtifactGenError> }`: missing `---END---` → `.truncated`; missing `---PAYLOAD---`, bad header JSON or `kind` not `spec`/`app` → `.malformedEnvelope`; header may be wrapped in code fences; title trimmed, capped at 60, empty → `"Untitled"`.
  - `enum ArtifactPrompts { static let payloadMarker = "---PAYLOAD---"; static let endMarker = "---END---"; static let currentPayloadHeader = "CURRENT PAYLOAD:"; static func systemInstruction(registry:language:allowedKinds:) -> String; static func updatePrompt(change:currentTitle:currentPayload:) -> String; static func retryAddendum(for: ArtifactGenError) -> String }`. The system text states the envelope format, `SpecBlock.catalog`, a size budget (≤ 40 blocks, short text), the visible-text language, and `registry.manual(including: [.read])` when `allowedKinds == [.spec]`.
  - `struct ArtifactDraft: Equatable { kind; title; payload: Data; requests: [String]; prompt: String }`
  - `enum ArtifactGeneratorLimits { static let minRequestLength = 3, maxRequestLength = 4_000, maxTitleLength = 60 }`
  - `struct ArtifactGenerator { let ai: AIClient; let registry: CapabilityRegistry; var language: SupportedLanguage = .english; var allowedKinds: Set<ArtifactKind> = [.spec]; func create(request: String, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError>; func update(kind: ArtifactKind, currentTitle: String, currentPayload: Data, change: String, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError> }`. Calls `generateJSON(prompt:, systemInstruction:, schema: nil, …, temperature: 0.4)` with the user's literal request as `prompt`. Flow: parse → kind in `allowedKinds` else `.kindNotAvailable` → `SpecValidator.decode` + `validate` → payload re-encoded with sorted keys. One retry (prompt + `retryAddendum`) on `.truncated` or `.invalidSpec`; `.ai` errors never retry. `update` keeps `currentTitle`; a `.truncated` after the retry becomes `.tooLargeToExtend`.
  - Mock change: `private(set) var generateJSONCalls: [(prompt: String, systemInstruction: String, schema: [String: Any]?)]` and `var generateJSONScript: [Result<String, AIError>]` consumed before `generateJSONResult`.

- [ ] **Step 1: Write failing tests.** Parser: `testMissingEndIsTruncated`, `testMissingPayloadMarkerIsMalformed`, `testBadKindIsMalformed`, `testFencedHeaderParses`, `testTitleCappedAndDefaulted`. Generator (MockAIClient + `CapabilityProviders.registry` over in-memory repos):

```swift
func testCreateSendsLiteralRequestAndEveryCapabilityName() async {
    _ = await generator.create(request: "table of Spanish weekdays", apiKey: "k", model: model)
    let call = ai.generateJSONCalls.last!
    XCTAssertEqual(call.prompt, "table of Spanish weekdays")
    XCTAssertNil(call.schema)
    for name in ["library.words", "library.word", "stats.wordsPerDay", "stats.wordsPerWeek"] { XCTAssertTrue(call.systemInstruction.contains(name)) }
    XCTAssertTrue(call.systemInstruction.contains("---PAYLOAD---"))
    XCTAssertFalse(call.systemInstruction.contains("storage.set")) // spec kind lists read capabilities only
}
func testArabicLanguageNamedInSystemInstruction()
func testRequestTooShortIsRejectedWithoutCallingAI() // 0 calls
func testTruncatedRetriesOnceThenSucceeds()   // script [truncated, valid] → 2 calls, 2nd prompt contains retryAddendum text
func testTruncatedTwiceFails()                // .failure(.truncated), 2 calls
func testInvalidSpecRetriesOnceThenFails()
func testAIErrorIsNotRetried()                // script [.failure(.rateLimited)] → .failure(.ai(.rateLimited)), 1 call
func testAppKindRejectedWhenNotAllowed()      // .kindNotAvailable
func testCreateReturnsSanitizedSpecPayload()  // blocks capped, decodes back
func testUpdatePromptContainsCurrentPayloadAndChange() // prompt contains "CURRENT PAYLOAD:", the payload JSON, and the change
func testUpdateKeepsTitle()
func testUpdateTruncatedBecomesTooLargeToExtend()
```

- [ ] **Step 2: Verify RED by eye.** Run: `grep -n "generateJSONCalls" PalabraTests/Support/MockAIClient.swift` — Expected: no output.
- [ ] **Step 3: Implement** the Mock change, then the three AI files.
- [ ] **Step 4: Commit** `feat(artifacts): envelope, prompts and generator`.

---

### Task 6: Spec renderer, bind loader, tick state

**Files:** Create `Spec/SpecBindLoader.swift`, `Spec/SpecStateStore.swift`, `Spec/SpecRenderer.swift`, `Spec/SpecTableView.swift`, `Spec/SpecChartView.swift`, `Spec/SpecChecklistViews.swift`; Test `PalabraTests/Artifacts/{SpecBindLoaderTests,SpecStateStoreTests}.swift`.

**Interfaces:**
- Consumes: `ArtifactSpec`, `SpecBind`, `CapabilityRegistry.call`, `GrantPolicy.effectiveGrant`, `ArtifactRepository.stateValue/setStateValue`.
- Produces:
  - `enum SpecBindResult<T: Equatable>: Equatable { case loaded(T), failed(String) }`; `struct ResolvedTable: Equatable { columns: [String]; rows: [[String]] }`; `struct ResolvedChart: Equatable { labels: [String]; values: [Double] }`
  - `enum SpecBindLoader { static func table(_ t: SpecTable, registry:, session:, granted:) async -> SpecBindResult<ResolvedTable>; static func chart(_ c: SpecChart, registry:, session:, granted:) async -> SpecBindResult<ResolvedChart> }` — inline data passes through; a bind calls the registry; rows come from an array of objects via each column's `field ?? title`; values stringified (integral numbers without `.0`, arrays joined with `", "`, null → `""`); tables capped at 200 rows, charts at 500 points; a registry failure or non-array result → `.failed("Couldn't load data")`.
  - `protocol SpecStateStore: AnyObject { func completed(blockID: String) -> Set<Int>; func setCompleted(blockID: String, _ indices: Set<Int>) }`; `final class InMemorySpecStateStore` (drafts); `final class ArtifactSpecStateStore(artifactID: UUID, repository: ArtifactRepository)` persisting JSON `[Int]` under key `spec.<blockID>`.
  - `struct SpecRendererView: View { init(spec: ArtifactSpec, registry: CapabilityRegistry, session: ArtifactSession, state: SpecStateStore) }` — blocks per the Task 3 shapes; bound blocks load in `.task` and again on `scenePhase == .active`; `Text(verbatim:)` for every AI string; `ForEach(Array(x.enumerated()), id: \.offset)`; charts via `import Charts` (`BarMark`/`LineMark`); tables scroll horizontally inside their own container; layout direction follows the environment.

- [ ] **Step 1: Write failing tests:** `testInlineTablePassesThrough`; `testBoundTableMapsFields` (registry stub returning `[{"spanish":"hola","translation":"hello"}]`, columns by `field`); `testColumnWithoutFieldUsesTitle`; `testStringification` (`3` → `"3"`, `2.5` → `"2.5"`, `[ "a","b" ]` → `"a, b"`, null → `""`); `testBoundChartMapsLabelAndValue`; `testRowCapAt200`; `testEmptyResultIsLoadedEmpty` (empty library); `testUngrantedBindFails` (`.failed("Couldn't load data")`); `testNonArrayResultFails`; `testChecklistStateRoundTripInMemory`; `testChecklistStatePersistsInRepository` (separate store instances over one repository see the same indices); `testChecklistStateOverflowIsIgnoredNotCrashing`.
- [ ] **Step 2: Verify RED by eye.** Run: `ls Palabra/Features/Artifacts/Spec/SpecBindLoader.swift 2>&1` — Expected: no such file.
- [ ] **Step 3: Implement** loader and stores, then the views (one file per view family; each stays well under 200 lines).
- [ ] **Step 4: Commit** `feat(artifacts): spec renderer with live bindings`.

---

### Task 7: Artifacts page, wiring, stub, UI tests, docs

**Files:** Create `Library/{ArtifactsListView,ArtifactDraftModel,ArtifactDraftView,ArtifactDetailView}.swift`, `PalabraTests/Artifacts/StubArtifactTests.swift`, `PalabraUITests/ArtifactsUITests.swift`, `docs/features/artifacts.md`; Modify `Router.swift`, `RootView.swift`, `SpanishHomeView.swift`, `AppEnvironment.swift`, `StubAIClient.swift`, `UITestHelpers.swift`, `ar.lproj/Localizable.strings`, `LocalizationTests.swift`, `AGENTS.md`.

**Interfaces:**
- Consumes: Tasks 1–6; `NotesDeckModel` as the pattern for key/model/repair handling; `ErrorBanner`, `EmptyStateView`.
- Produces:
  - `Router.Destination` gains `.artifacts` and `.artifactDetail(UUID)`; `SpanishHomeView` gains a second row "Artifacts" (`sparkles`, identifier `spanishRow.artifacts`); `RootView` resolves both.
  - `AppEnvironment.capabilities: CapabilityRegistry` = `CapabilityProviders.registry(words: repository, artifacts: artifacts)`, built in `init`.
  - `@MainActor @Observable final class ArtifactDraftModel` with `enum Mode { case create; case update(artifactID: UUID) }`, `enum Phase: Equatable { case input, generating, preview, failed(ArtifactGenError) }`, `var request: String`, `private(set) var draft: ArtifactDraft?`, `generate() async`, `refine(change: String) async` (runs `update` against the draft), `save() -> UUID?` (create → `artifacts.create`; update → `artifacts.addVersion`), `discard()`. Key/model/repair logic mirrors `NotesDeckModel.run`.
  - `ArtifactDraftView` (sheet): input → generating → preview (renders `SpecRendererView` with `ArtifactSession(artifactID: nil, dryRun: true)` and an `InMemorySpecStateStore`) with Save, Refine, Discard.
  - `ArtifactsListView`: `@Query(sort: \Artifact.updatedAt, order: .reverse)`; empty state "No artifacts yet"; toolbar `newArtifactButton`; rows push `.artifactDetail`; swipe/confirm delete.
  - `ArtifactDetailView(artifactID:)`: renders the current version through `ArtifactSpecStateStore`; menu `artifactMenu` → Update (draft sheet in update mode), Versions (list with Restore per row), Delete. A `kind == .app` artifact shows an `EmptyStateView` "Not supported in this version yet".
  - Accessibility identifiers: `artifactRequestField`, `generateArtifactButton`, `saveArtifactButton`, `refineArtifactField`, `refineArtifactButton`, `discardArtifactButton`, `artifactMenu`, `artifactRow`, `restoreVersion-<n>`.
  - `StubAIClient.generateJSON`: when `schema == nil` and `systemInstruction` contains `---PAYLOAD---`: prompt containing `fallo` → `.failure(.rateLimited)`; prompt containing `CURRENT PAYLOAD:` → the create envelope plus a `text` block `"Updated"`; otherwise this envelope (existing Study behaviour unchanged):

```
{"kind":"spec","title":"Stub artifact","requests":["library.words"]}
---PAYLOAD---
{"blocks":[{"type":"heading","level":1,"text":"Stub artifact"},{"type":"list","ordered":false,"items":["Same","Same"]},{"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{"limit":10}}},{"type":"checklist","id":"c1","items":["First step","Second step"]}]}
---END---
```

  - `extension XCUIApplication { @discardableResult func openHubRow(_ identifier: String, expectingNavigationBar title: String, timeout: TimeInterval = 10) -> Bool }`; `openVocabulary()` becomes a call to it.

- [ ] **Step 1: Write failing tests.** `StubArtifactTests` (keeps stub and prompts in sync): `testStubCreateParsesThroughGenerator` (real `ArtifactGenerator` with `StubAIClient`: success, title `"Stub artifact"`, 4 blocks, `requests == ["library.words"]`); `testStubUpdateAddsUpdatedBlock` (5 blocks, last is text `"Updated"`); `testStubFailurePath` (`.failure(.ai(.rateLimited))`). `LocalizationTests.testArabicStringsHaveArtifactKeys`: every key in this list has a non-empty value — `Artifacts`, `New Artifact`, `No artifacts yet`, `Ask the AI for a table, chart, roadmap or checklist.`, `Describe what you want`, `Generate`, `Generating…`, `Save`, `Refine`, `Discard`, `Update`, `Versions`, `Restore`, `Delete`, `Couldn't load data`, `Not supported in this version yet`. UI tests (`ArtifactsUITests`, stub AI, launch `-UITestStub -UITestReset -UITestSeed 3`):

```swift
func testCreateSaveOpenUpdateAndRestore() {
    app.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts")
    app.buttons["newArtifactButton"].tap()
    field("artifactRequestField").typeText("a table of my words"); app.buttons["generateArtifactButton"].tap()
    XCTAssertTrue(app.staticTexts["Stub artifact"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["palabra0"].waitForExistence(timeout: 5))   // live bind to library.words
    app.buttons["saveArtifactButton"].tap()
    XCTAssertTrue(app.buttons["artifactRow"].firstMatch.waitForExistence(timeout: 5)); app.buttons["artifactRow"].firstMatch.tap()
    // update: artifactMenu → Update → type change → generate → Save → "Updated" visible
    // versions: artifactMenu → Versions → restoreVersion-1 → "Updated" no longer visible
}
func testFailurePathShowsRetry()            // request "fallo" → ErrorBanner with Retry
func testChecklistTickSurvivesRelaunch()    // -UITestPersist: tick "First step", relaunch, still ticked
```

- [ ] **Step 2: Verify RED by eye.** Run: `grep -n "payloadMarker\|PAYLOAD" Palabra/Core/AI/StubAIClient.swift` — Expected: no output.
- [ ] **Step 3: Implement** wiring, stub, then the four library files; add the Arabic strings listed above.
- [ ] **Step 4: Document.** `docs/features/artifacts.md` (architecture, wire format, limits, how to add a capability: one `Capability` in a provider, nothing else); `AGENTS.md`: layout entry for `Features/Artifacts/`, a rules section "Artifacts" (registry is the only door; providers live in `App/`; spec artifacts never prompt; persisted names; stub/prompt sync test), update the "Known places" note that `AppEnvironment` also owns `artifacts` and `capabilities`.
- [ ] **Step 5: Verify by eye.** Run: `grep -rn "withAnimation\|\.animation(" Palabra/Features/Artifacts` — Expected: no output; and `grep -rnw "Word\|Deck\|Card" Palabra/Features/Artifacts` — Expected: no output.
- [ ] **Step 6: Commit** `feat(artifacts): Artifacts page with create, update and restore`.
- [ ] **Step 7: Deliver and verify on CI.** Zip the changed files for the Codespace (no push unless asked). After the commits are on `main`: `curl -s -H "Authorization: token $PAT" "https://api.github.com/repos/Hocine123321/Palabra/actions/runs?per_page=1"` — Expected: `completed` / `success` for `ipa` and `tests`; fix any red run before plan B2.
