import XCTest
@testable import Palabra

final class ContentValidatorTests: XCTestCase {
    private func validContent() -> WordContent {
        WordContent(
            word: "  hablar  ",
            examples: [
                .init(context: "At school", spanish: "Hablo español en clase.", english: "I speak Spanish in class."),
                .init(context: "With friends", spanish: "¿Puedes hablar más despacio?", english: "Can you speak more slowly?"),
                .init(context: "On the phone", spanish: "Necesito hablar con el médico.", english: "I need to speak with the doctor.")
            ],
            meaning: .init(translations: ["to speak", "to talk"], explanation: "Used for speaking or talking."),
            usage: .init(explanation: "A regular -ar verb.", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [
                .init(label: "Present", items: [.init(form: "hablo", note: nil), .init(form: "hablas", note: nil)])
            ]),
            similarWords: [.init(word: "conversar", difference: "More formal, implies a two-way conversation.")]
        )
    }

    func testValidContentPassesAndIsTrimmed() {
        let result = ContentValidator.validate(validContent())
        switch result {
        case .success(let content):
            XCTAssertEqual(content.word, "hablar")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testMissingWordFails() {
        var c = validContent()
        c.word = "   "
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("word"))
    }

    func testWrongExampleCountFails() {
        var c = validContent()
        c.examples = Array(c.examples.prefix(2))
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("examples.count"))
    }

    func testDuplicateExampleParagraphsFail() {
        var c = validContent()
        c.examples[1] = c.examples[0]
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("examples.distinct"))
    }

    func testEmptyTranslationsFail() {
        var c = validContent()
        c.meaning.translations = []
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("meaning.translations"))
    }

    func testEmptyFormGroupsFail() {
        var c = validContent()
        c.forms.groups = []
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("forms.groups"))
    }

    func testEmptySimilarWordsFail() {
        var c = validContent()
        c.similarWords = []
        guard case .failure(.validationFailed(let fields)) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertTrue(fields.contains("similarWords"))
    }

    func testSimilarWordsBeyondEightAreTruncated() {
        var c = validContent()
        c.similarWords = (0..<10).map { .init(word: "palabra\($0)", difference: "differs") }
        guard case .success(let content) = ContentValidator.validate(c) else { return XCTFail() }
        XCTAssertEqual(content.similarWords.count, 8)
    }
}
