# Plan A: Spanish Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `Vocabulary` tab to `Spanish` and make it a hub page list whose only row (for now) opens the existing library.

**Architecture:** `RootView`'s first tab keeps one `NavigationStack`, whose root becomes a new `SpanishHomeView`. `Router.path` becomes a typed `[Router.Destination]` (testable), gains a `.vocabulary` destination, and `openWord` stacks the library under the word detail so Back lands on the library. No persisted names change.

**Tech Stack:** SwiftUI (iOS 17), XCTest, XCUITest, XcodeGen, GitHub Actions CI (the only compiler).

**Spec:** `docs/superpowers/specs/2026-10-06-artifacts-design.md` §10 (Spanish hub), §2 (this is plan A of A, B1, B2, C, D+).

## Global Constraints

- Deployment target iOS 17.0; `SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY targeted`.
- Dependency direction: `Features/Spanish` must not import Vocabulary internals; the stack root links only by `Router.Destination` values, and `RootView` (App/) resolves them.
- Design system: `List` screen uses `.creamScreen()` and `Section { }.themedSection()`; row text `Theme.Font.rowTitle`; no `.tint`, no numeric radii, no `withAnimation`.
- Localization is keyed by the English string in `Resources/ar.lproj/Localizable.strings`; UI tests find elements by English text.
- Tab label "Spanish"; hub navigation title "Spanish"; Vocabulary row title "Vocabulary"; the library keeps its navigation title "Library". Tab and row icon stays `text.book.closed`.
- This plan adds only the `.vocabulary` destination. `.artifacts`/`.artifactDetail` (plan B1) and `.needReview` (plan C) are added by those plans; no dead rows.
- No persisted names change (`AppTab`, `Router`, `Router.Destination` are not persisted).
- Everything is compiled by eye only. Tasks 1 and 2 must land in one push (after Task 1 alone the UI tests are red).

## Review Focus

1. `openWord` while the library is already pushed (`path == [.vocabulary]`) must not push a second library. Test: `testOpenWordFromLibraryKeepsLibraryAndAddsDetail`.
2. `openWord` while another word's detail is open replaces that detail, never stacks. Test: `testOpenWordReplacesAnExistingDetail`.
3. `openSettings()` changes only the tab and leaves the Spanish stack intact. Test: `testOpenSettingsChangesOnlyTheTab`.
4. A missing Arabic key renders English text inside an RTL layout. Test: `testArabicStringsHaveSpanishHubKey`.
5. Back from a word detail lands on the library, not the hub. Test: assertion added to `SmokeUITests` (Task 2).

## File Structure

| File | Responsibility |
|---|---|
| `Palabra/App/Router.swift` (modify) | `AppTab.spanish`, `[Destination]` path, `.vocabulary`, `openWord` |
| `Palabra/Features/Spanish/SpanishHomeView.swift` (create) | Hub page list |
| `Palabra/App/RootView.swift` (modify) | Stack root, destination switch, tab label/tag |
| `Palabra/Resources/ar.lproj/Localizable.strings` (modify) | Arabic for "Spanish" |
| `PalabraTests/App/RouterTests.swift` (create) | Router behavior |
| `PalabraTests/App/LocalizationTests.swift` (create) | Hub key present in Arabic table |
| `PalabraUITests/UITestHelpers.swift` (create) | `openVocabulary()` |
| `PalabraUITests/{Launch,VocabularyLibrary,Smoke,Persistence}UITests.swift` (modify) | Go through the hub |
| `AGENTS.md` (modify) | Tabs, layout, router notes |

---

### Task 1: Hub navigation

**Files:**
- Modify: `Palabra/App/Router.swift`, `Palabra/App/RootView.swift`, `Palabra/Resources/ar.lproj/Localizable.strings`, `AGENTS.md`
- Create: `Palabra/Features/Spanish/SpanishHomeView.swift`, `PalabraTests/App/RouterTests.swift`, `PalabraTests/App/LocalizationTests.swift`

**Interfaces:**
- Consumes: `VocabularyLibraryView()` (no parameters), `WordDetailHost(wordID:)`, `Theme.Font.rowTitle`, `creamScreen()`, `themedSection()`.
- Produces:
  - `enum AppTab: Hashable { case spanish, study, settings }`
  - `Router.Destination: Hashable { case vocabulary; case wordDetail(UUID) }`
  - `Router.path: [Router.Destination]`; `Router.tab: AppTab = .spanish`
  - `Router.openWord(_ id: UUID)` sets `tab = .spanish`, `path = [.vocabulary, .wordDetail(id)]`
  - `Router.openSettings()` unchanged
  - `struct SpanishHomeView: View` (no parameters); the Vocabulary row has accessibility identifier `spanishRow.vocabulary`

- [ ] **Step 1: Write `RouterTests` (`@MainActor final class RouterTests: XCTestCase`, `@testable import Palabra`)**

```swift
func testDefaultsToSpanishTabWithEmptyPath() {
    let router = Router()
    XCTAssertEqual(router.tab, .spanish)
    XCTAssertEqual(router.path, [])
}
func testOpenWordFromAnotherTabSelectsSpanishAndStacksLibraryUnderDetail() {
    let router = Router(); let id = UUID()
    router.tab = .study
    router.openWord(id)
    XCTAssertEqual(router.tab, .spanish)
    XCTAssertEqual(router.path, [.vocabulary, .wordDetail(id)])
}
func testOpenWordFromLibraryKeepsLibraryAndAddsDetail() {
    let router = Router(); let id = UUID()
    router.path = [.vocabulary]
    router.openWord(id)
    XCTAssertEqual(router.path, [.vocabulary, .wordDetail(id)])
}
func testOpenWordReplacesAnExistingDetail() {
    let router = Router(); let a = UUID(), b = UUID()
    router.path = [.vocabulary, .wordDetail(a)]
    router.openWord(b)
    XCTAssertEqual(router.path, [.vocabulary, .wordDetail(b)])
}
func testOpenSettingsChangesOnlyTheTab() {
    let router = Router()
    router.path = [.vocabulary]
    router.openSettings()
    XCTAssertEqual(router.tab, .settings)
    XCTAssertEqual(router.path, [.vocabulary])
}
```

- [ ] **Step 2: Write `LocalizationTests.testArabicStringsHaveSpanishHubKey`**

Load `Bundle(for: Router.self).url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ar")`, read it with `NSDictionary(contentsOf:) as? [String: String]`, and `XCTAssertFalse((table["Spanish"] ?? "").isEmpty)`.

- [ ] **Step 3: Confirm the tests cannot compile yet**

Run: `grep -n "case spanish" Palabra/App/Router.swift`
Expected: no output (the tests reference `.spanish` and `.vocabulary`, which do not exist yet).

- [ ] **Step 4: Update `Router.swift`**

Rename `AppTab.vocabulary` to `.spanish`; add `case vocabulary` to `Router.Destination`; change `var path` to `[Destination] = []` and `var tab: AppTab = .spanish`; implement `openWord(_:)` per the Produces block. Update the doc comment on `Destination` to say "Pushed screens of the Spanish tab only."

- [ ] **Step 5: Create `SpanishHomeView`**

`List { Section { NavigationLink(value: Router.Destination.vocabulary) { Label("Vocabulary", systemImage: "text.book.closed").font(Theme.Font.rowTitle) }.accessibilityIdentifier("spanishRow.vocabulary") }.themedSection() }` with `.creamScreen()` and `.navigationTitle("Spanish")`.

- [ ] **Step 6: Update `RootView`**

First tab: `NavigationStack(path: $env.router.path) { SpanishHomeView().navigationDestination(for: Router.Destination.self) { ... } }`; the switch handles `.vocabulary` → `VocabularyLibraryView()` and `.wordDetail(let id)` → `WordDetailHost(wordID: id)`; `.tabItem { Label("Spanish", systemImage: "text.book.closed") }`; `.tag(AppTab.spanish)`.

- [ ] **Step 7: Add the Arabic string**

Append to `ar.lproj/Localizable.strings`, after a `/* Spanish hub */` comment line: `"Spanish" = "الإسبانية";`. ("Vocabulary" already exists.)

- [ ] **Step 8: Update `AGENTS.md`**

Change the two "Vocabulary, Study and Settings tabs" mentions (line ~10, ~101, ~154) to "Spanish, Study and Settings"; add `Spanish/ hub page list (SpanishHomeView)` under `Features/` in the Layout block; in the Tabs bullet add: "The Spanish tab's stack root is `SpanishHomeView`; `Router.path` is `[Router.Destination]` and `openWord` stacks `.vocabulary` under `.wordDetail`. New hub pages add a `Router.Destination` case and a row in `SpanishHomeView`."

- [ ] **Step 9: Verify by eye**

Run: `grep -rn "AppTab.vocabulary\|NavigationPath\|\.tag(AppTab.vocabulary)" Palabra PalabraTests`
Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add Palabra PalabraTests AGENTS.md
git commit -m "feat: Spanish hub tab with Vocabulary row; typed router path"
```

---

### Task 2: UI tests through the hub

**Files:**
- Create: `PalabraUITests/UITestHelpers.swift`
- Modify: `PalabraUITests/LaunchUITests.swift`, `VocabularyLibraryUITests.swift`, `SmokeUITests.swift`, `PersistenceUITests.swift`

**Interfaces:**
- Consumes: nav title "Spanish", row identifier `spanishRow.vocabulary`, library nav title "Library" (all from Task 1).
- Produces: `extension XCUIApplication { @discardableResult func openVocabulary(timeout: TimeInterval = 10) -> Bool }`

- [ ] **Step 1: Implement `openVocabulary`**

Find the element via `descendants(matching: .any).matching(identifier: "spanishRow.vocabulary").firstMatch` (type-agnostic: SwiftUI list links can surface as button or cell), wait for it (`XCTFail` and return `false` if missing), tap it, return `navigationBars["Library"].waitForExistence(timeout: timeout)`.

- [ ] **Step 2: Rewrite `LaunchUITests`**

Replace `testAppLaunchesToLibrary` with:

```swift
func testAppLaunchesToSpanishHub() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestStub", "-UITestReset"]
    app.launch()
    XCTAssertTrue(app.navigationBars["Spanish"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.tabBars.buttons["Spanish"].exists)
}
func testVocabularyRowOpensLibrary() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestStub", "-UITestReset"]
    app.launch()
    XCTAssertTrue(app.openVocabulary())
}
```

- [ ] **Step 3: Route the other tests through the hub**

Insert `XCTAssertTrue(app.openVocabulary())` right after `app.launch()` in both `VocabularyLibraryUITests` tests and `SmokeUITests`; in `PersistenceUITests` do the same for `addApp` and for `relaunchApp` (use the matching variable names).

- [ ] **Step 4: Pin Review Focus 5 in `SmokeUITests`**

After the existing `app.navigationBars.buttons.element(boundBy: 0).tap()` (back from detail) and before the Settings tab tap, add `XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))`.

- [ ] **Step 5: Verify by eye**

Run: `grep -n "app.launch()\|addApp.launch()\|relaunchApp.launch()" PalabraUITests/{Smoke,Persistence,VocabularyLibrary}UITests.swift`
Expected: every match is followed within 2 lines by an `openVocabulary()` call.

- [ ] **Step 6: Commit**

```bash
git add PalabraUITests
git commit -m "test: UI tests enter the library through the Spanish hub"
```

- [ ] **Step 7: Deliver and verify on CI**

Package the changed files as a zip for the Codespace (do not push unless asked). Once the commits are on `main`, check CI: `curl -s -H "Authorization: token $PAT" "https://api.github.com/repos/Hocine123321/Palabra/actions/runs?per_page=1"`.
Expected: latest run `completed` / `success` for both the `ipa` and `tests` jobs; a red run is fixed before plan B1 starts.
