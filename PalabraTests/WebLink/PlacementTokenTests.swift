import XCTest
@testable import Palabra

/// The same vectors as web/test/token.test.js. If one side changes, change both.
final class PlacementTokenTests: XCTestCase {
    func testAgreedVectors() {
        let vectors: [(String?, [String], String)] = [
            (nil, [], "|"),
            ("Food", [], "Food|"),
            ("Food", ["b", "a"], "Food|a,b"),
            (nil, ["z", "a", "m"], "|a,m,z"),
            ("a|b", ["c,d"], "a\\|b|c\\,d"),
            ("back\\slash", [], "back\\\\slash|"),
            ("Café", ["niño", "año"], "Café|año,niño"),
            (nil, ["\u{1F600}", "\u{FF5E}"], "|\u{FF5E},\u{1F600}"),   // UTF-8 puts U+FF5E first
        ]
        for (category, tags, expected) in vectors {
            XCTAssertEqual(PlacementToken.make(category: category, tags: tags), expected, "\(String(describing: category)) \(tags)")
        }
    }

    func testDifferentPlacementsNeverShareATokenAndTagOrderDoesNotMatter() {
        XCTAssertNotEqual(PlacementToken.make(category: "a|b", tags: []), PlacementToken.make(category: "a", tags: ["b"]))
        XCTAssertNotEqual(PlacementToken.make(category: "a", tags: ["b,c"]), PlacementToken.make(category: "a", tags: ["b", "c"]))
        XCTAssertEqual(PlacementToken.make(category: "x", tags: ["b", "a"]), PlacementToken.make(category: "x", tags: ["a", "b"]))
    }
}
