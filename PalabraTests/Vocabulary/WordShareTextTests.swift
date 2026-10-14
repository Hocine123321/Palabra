import XCTest
@testable import Palabra

final class WordShareTextTests: XCTestCase {
    private func content(translations: [String], examples: [WordContent.Example]) -> WordContent {
        WordContent(
            word: "hablar",
            examples: examples,
            meaning: .init(translations: translations, explanation: "Used for speaking."),
            usage: .init(explanation: "A regular -ar verb.", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: []),
            similarWords: []
        )
    }

    func testWordMeaningAndFirstExample() {
        let text = WordShareText.make(content(translations: ["to speak", "to talk"], examples: [
            .init(context: "School", spanish: "Hablo espa\u{00F1}ol.", english: "I speak Spanish."),
            .init(context: "Phone", spanish: "Otro.", english: "Another."),
        ]))
        XCTAssertEqual(text, "hablar \u{2014} to speak, to talk\n\nHablo espa\u{00F1}ol.\nI speak Spanish.")
    }

    func testWithoutTranslationsOrExamplesIsJustTheWord() {
        XCTAssertEqual(WordShareText.make(content(translations: [], examples: [])), "hablar")
        XCTAssertEqual(WordShareText.make(content(translations: ["", ""], examples: [])), "hablar")
    }
}
