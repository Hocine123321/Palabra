import XCTest
@testable import Palabra

final class WordKeyTests: XCTestCase {
    func testIdentityTrimsAndLowercases() {
        XCTAssertEqual(WordKey.identity("  Hola  "), "hola")
    }

    func testIdentityCollapsesInternalWhitespace() {
        XCTAssertEqual(WordKey.identity("de   nada"), "de nada")
    }

    func testIdentityKeepsDiacriticsSignificant() {
        XCTAssertEqual(WordKey.identity("Año"), "año")
        XCTAssertNotEqual(WordKey.identity("el"), WordKey.identity("él"))
        XCTAssertNotEqual(WordKey.identity("año"), WordKey.identity("ano"))
    }

    func testSearchFoldsDiacritics() {
        XCTAssertEqual(WordKey.search("año"), WordKey.search("ano"))
        XCTAssertEqual(WordKey.search("MAÑANA"), WordKey.search("mañana"))
    }

    func testTintIndexIsDeterministicAndInRange() {
        let a = WordKey.tintIndex("hola", count: 6)
        let b = WordKey.tintIndex("hola", count: 6)
        XCTAssertEqual(a, b)
        XCTAssertTrue((0..<6).contains(a))
    }

    func testTintIndexZeroCountIsZero() {
        XCTAssertEqual(WordKey.tintIndex("x", count: 0), 0)
    }
}
