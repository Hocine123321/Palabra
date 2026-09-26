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
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertNil(store.selectedModelID)
    }

    func testValuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.selectedModelID = "models/gemini-2.5-flash"
        store.libraryLayout = .list
        store.hasCompletedOnboarding = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedModelID, "models/gemini-2.5-flash")
        XCTAssertEqual(reloaded.libraryLayout, .list)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
