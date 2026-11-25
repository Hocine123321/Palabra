import XCTest
@testable import Palabra

final class SpellSuggestionTests: XCTestCase {
    private struct StubGuesser: SpellGuessing {
        var table: [String: [String]] = [:]
        func guesses(for word: String) -> [String] { table[word] ?? [] }
    }

    private func suggest(_ input: String, _ table: [String: [String]]) -> String? {
        SpellSuggestion.suggestion(for: input, guesser: StubGuesser(table: table))
    }

    func testSuggestsTheNearestCorrection() {
        XCTAssertEqual(suggest("tambien", ["tambien": ["también"]]), "también")
        XCTAssertEqual(suggest("hablr", ["hablr": ["Hablar"]]), "hablar")
    }

    func testNoGuessesMeansNoSuggestion() {
        XCTAssertNil(suggest("hola", [:]))
    }

    func testPhrasesAndOddInputAreLeftAlone() {
        XCTAssertNil(suggest("de nada", ["de nada": ["denada"]]))
        XCTAssertNil(suggest("ab", ["ab": ["abc"]]))
        XCTAssertNil(suggest("palabra0", ["palabra0": ["palabra"]]))
        XCTAssertNil(suggest(String(repeating: "a", count: 31), [String(repeating: "a", count: 31): ["aaa"]]))
    }

    func testAGuessFarFromWhatWasTypedIsIgnored() {
        XCTAssertNil(suggest("xyz", ["xyz": ["abcdefg"]]))
    }

    func testASameWordGuessAndMultiWordGuessAreSkipped() {
        XCTAssertNil(suggest("gato", ["gato": ["gato", "ga to"]]))
        XCTAssertEqual(suggest("gato", ["gato": ["ga to", "gata"]]), "gata")
    }

    func testEditDistance() {
        XCTAssertEqual(SpellSuggestion.editDistance("gato", "gato"), 0)
        XCTAssertEqual(SpellSuggestion.editDistance("gato", "gata"), 1)
        XCTAssertEqual(SpellSuggestion.editDistance("", "abc"), 3)
        XCTAssertEqual(SpellSuggestion.editDistance("abc", ""), 3)
        XCTAssertEqual(SpellSuggestion.editDistance("kitten", "sitting"), 3)
    }
}
