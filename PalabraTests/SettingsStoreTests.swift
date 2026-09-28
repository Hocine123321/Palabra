import XCTest
@testable import Palabra

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "dev.palabra.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreGridLayoutAndIncompleteOnboarding() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.libraryLayout, .grid)
        XCTAssertEqual(store.appearanceMode, .system)
        XCTAssertEqual(store.appLanguage, .english)
        XCTAssertEqual(store.aiLanguage, .english)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertNil(store.selectedModelID)
        XCTAssertNil(store.selectedTTSModelID)
    }

    func testValuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.selectedModelID = "models/gemini-2.5-flash"
        store.selectedTTSModelID = "models/gemini-2.5-flash-tts"
        store.libraryLayout = .list
        store.appearanceMode = .dark
        store.appLanguage = .arabic
        store.aiLanguage = .arabic
        store.hasCompletedOnboarding = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedModelID, "models/gemini-2.5-flash")
        XCTAssertEqual(reloaded.selectedTTSModelID, "models/gemini-2.5-flash-tts")
        XCTAssertEqual(reloaded.libraryLayout, .list)
        XCTAssertEqual(reloaded.appearanceMode, .dark)
        XCTAssertEqual(reloaded.appLanguage, .arabic)
        XCTAssertEqual(reloaded.aiLanguage, .arabic)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
