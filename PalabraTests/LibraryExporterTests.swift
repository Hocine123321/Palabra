import XCTest
@testable import Palabra

final class LibraryExporterTests: XCTestCase {
    private func item(word: String = "hablar") -> LibraryExporter.Item {
        let content = WordContent(
            word: word,
            examples: [
                .init(context: "a", spanish: "Dijo \"hola\".", english: "He said \"hi\".\nA second line."),
                .init(context: "b", spanish: "¡Vamos! 🎉", english: "Let's go! 🎉"),
                .init(context: "c", spanish: "tres", english: "three")
            ],
            meaning: .init(translations: ["to speak"], explanation: "explanation"),
            usage: .init(explanation: "usage", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: "hablo", note: nil)])]),
            similarWords: [.init(word: "conversar", difference: "more formal")]
        )
        return LibraryExporter.Item(
            content: content,
            raw: Data("{}".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            chat: [ChatMessage(role: .user, text: "¿Qué significa \"hablar\"?")]
        )
    }

    func testEncodeDecodeRoundTripsQuotesNewlinesAndEmoji() throws {
        let data = LibraryExporter.encode(items: [item()])
        let envelope = try LibraryExporter.decode(data)
        XCTAssertEqual(envelope.app, "Palabra")
        XCTAssertEqual(envelope.words.first?.content.examples[0].spanish, "Dijo \"hola\".")
        XCTAssertEqual(envelope.words.first?.content.examples[0].english, "He said \"hi\".\nA second line.")
        XCTAssertEqual(envelope.words.first?.content.examples[1].spanish, "¡Vamos! 🎉")
        XCTAssertEqual(envelope.words.first?.chat.first?.text, "¿Qué significa \"hablar\"?")
    }

    func testDecodeRejectsUnsupportedVersion() {
        struct BadEnvelope: Codable {
            var app = "Palabra"
            var version = 99
            var exportedAt = Date()
            var words: [LibraryExporter.Item] = []
        }
        let data = try! JSONEncoder().encode(BadEnvelope())
        XCTAssertThrowsError(try LibraryExporter.decode(data)) { error in
            XCTAssertEqual(error as? LibraryExporter.ExportError, .unsupportedVersion(99))
        }
    }

    func testDecodeRejectsMalformedData() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try LibraryExporter.decode(garbage)) { error in
            XCTAssertEqual(error as? LibraryExporter.ExportError, .malformed)
        }
    }
}
