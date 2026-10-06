import XCTest
@testable import Palabra

@MainActor
final class RouterTests: XCTestCase {
    func testDefaultsToSpanishTabWithEmptyPath() {
        let router = Router()
        XCTAssertEqual(router.tab, .spanish)
        XCTAssertEqual(router.path, [])
    }

    func testOpenWordFromAnotherTabSelectsSpanishAndStacksLibraryUnderDetail() {
        let router = Router()
        let id = UUID()
        router.tab = .study
        router.openWord(id)
        XCTAssertEqual(router.tab, .spanish)
        XCTAssertEqual(router.path, [.vocabulary, .wordDetail(id)])
    }

    // Library already pushed: must not push a second library.
    func testOpenWordFromLibraryKeepsLibraryAndAddsDetail() {
        let router = Router()
        let id = UUID()
        router.path = [.vocabulary]
        router.openWord(id)
        XCTAssertEqual(router.path, [.vocabulary, .wordDetail(id)])
    }

    // Another word's detail is open: replace it, never stack details.
    func testOpenWordReplacesAnExistingDetail() {
        let router = Router()
        let a = UUID(), b = UUID()
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
}
