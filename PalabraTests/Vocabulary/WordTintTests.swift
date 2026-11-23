import XCTest
@testable import Palabra

final class WordTintTests: XCTestCase {
    private func source(_ key: String, pos: String = "", mode: WordTintMode = .mixed, colorWords: Bool = true) -> WordTint.Source {
        WordTint.source(key: key, partOfSpeech: pos, mode: mode, colorWords: colorWords)
    }

    func testColourWordWinsInEveryMode() {
        let expected = WordTint.Source.colorWord(ColorWordMatch(family: .red, shade: .normal))
        for mode in WordTintMode.allCases {
            XCTAssertEqual(source("rojo", pos: "adjective", mode: mode), expected, "\(mode)")
        }
    }

    func testColourWordsCanBeSwitchedOff() {
        XCTAssertEqual(source("rojo", colorWords: false), .word("rojo"))
        XCTAssertEqual(source("rojo", mode: .calm, colorWords: false), .neutral)
    }

    func testMixedKeepsTheOriginalHashTint() {
        XCTAssertEqual(source("casa", pos: "noun"), .word("casa"))
    }

    func testPartOfSpeechGroupsByFoldedPartOfSpeech() {
        XCTAssertEqual(source("casa", pos: "Noun", mode: .partOfSpeech), .partOfSpeech("noun"))
        XCTAssertEqual(source("mesa", pos: " noun ", mode: .partOfSpeech), .partOfSpeech(" noun ".trimmingCharacters(in: .whitespaces)))
        XCTAssertEqual(WordTint.color(for: source("casa", pos: "noun", mode: .partOfSpeech)),
                       WordTint.color(for: source("mesa", pos: "noun", mode: .partOfSpeech)))
    }

    func testPartOfSpeechFallsBackToTheWordWhenEmpty() {
        XCTAssertEqual(source("casa", pos: "", mode: .partOfSpeech), .word("casa"))
    }

    func testCalmIsNeutralForNonColourWords() {
        XCTAssertEqual(source("casa", pos: "noun", mode: .calm), .neutral)
    }

    func testCardTintOnlyForColourWordsAndHonoursTheSetting() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "WordTintTests.\(UUID().uuidString)"))
        XCTAssertNotNil(WordTint.cardTint(front: "rojo", defaults: suite), "on by default")
        XCTAssertNil(WordTint.cardTint(front: "casa", defaults: suite))
        suite.set(false, forKey: WordTintKeys.colorWords)
        XCTAssertNil(WordTint.cardTint(front: "rojo", defaults: suite))
    }
}
