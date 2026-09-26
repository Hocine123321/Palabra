import XCTest
@testable import Palabra

final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore()

    override func tearDown() {
        store.delete()
        super.tearDown()
    }

    func testSaveThenReadRoundTrips() {
        XCTAssertTrue(store.save("AIzaSyExampleKeyValue1234"))
        XCTAssertEqual(store.read(), "AIzaSyExampleKeyValue1234")
    }

    func testSaveTrimsWhitespaceAndNewlines() {
        XCTAssertTrue(store.save("  AIzaSyExampleKeyValue1234  \n"))
        XCTAssertEqual(store.read(), "AIzaSyExampleKeyValue1234")
    }

    func testSaveReplacesPreviousValue() {
        XCTAssertTrue(store.save("first-key"))
        XCTAssertTrue(store.save("second-key"))
        XCTAssertEqual(store.read(), "second-key")
    }

    func testDeleteRemovesValue() {
        XCTAssertTrue(store.save("to-delete"))
        XCTAssertTrue(store.delete())
        XCTAssertNil(store.read())
    }

    func testReadWithoutSavingIsNil() {
        XCTAssertNil(store.read())
    }

    func testMaskLongKeyShowsLastFour() {
        XCTAssertEqual(KeychainStore.mask("AIzaSyExampleKeyValue1234"), "••••1234")
    }

    func testMaskShortKeyIsFullyMasked() {
        XCTAssertEqual(KeychainStore.mask("short1"), "••••")
    }
}
