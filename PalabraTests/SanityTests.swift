import XCTest

final class SanityTests: XCTestCase {
    func testHostAppIsPalabra() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.palabra.app")
    }
}
