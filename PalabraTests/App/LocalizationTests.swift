import XCTest
@testable import Palabra

final class LocalizationTests: XCTestCase {
    // Localization is keyed by the English string; a missing key shows English inside an RTL layout.
    func testArabicStringsHaveSpanishHubKey() throws {
        let url = try XCTUnwrap(
            Bundle(for: Router.self).url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ar")
        )
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertFalse((table["Spanish"] ?? "").isEmpty)
    }
}
