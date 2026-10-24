import XCTest
@testable import Palabra

final class LibraryKindTests: XCTestCase {
    func testOneWordIsAWord() {
        for headword in ["hola", "estás", "pan-dulce", "  hola  ", "¿qué?"] {
            XCTAssertFalse(LibraryKind.isPhrase(headword), headword)
            XCTAssertTrue(LibraryKind.words.includes(headword), headword)
            XCTAssertFalse(LibraryKind.phrases.includes(headword), headword)
        }
    }

    func testMoreThanOneWordIsAPhrase() {
        for headword in ["cómo estás", "como estas", "¿Cómo te llamas?", "dar a luz", "Buenos días a todos"] {
            XCTAssertTrue(LibraryKind.isPhrase(headword), headword)
            XCTAssertTrue(LibraryKind.phrases.includes(headword), headword)
            XCTAssertFalse(LibraryKind.words.includes(headword), headword)
        }
    }

    func testAllIncludesEverything() {
        XCTAssertTrue(LibraryKind.all.includes("hola"))
        XCTAssertTrue(LibraryKind.all.includes("cómo estás"))
    }

    func testEveryTabHasATitleToTranslate() {
        XCTAssertEqual(LibraryKind.allCases.map(\.title), ["All", "Words", "Phrases"])
    }
}
