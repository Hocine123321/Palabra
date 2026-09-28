import XCTest
@testable import Palabra

final class WordTests: XCTestCase {
    func testCorruptContentDataFallsBackToEmptyContent() {
        let word = Word(spanish: "hablar", key: "hablar", searchKey: "hablar", content: .empty, rawJSON: Data())
        word.contentData = Data("not valid json".utf8)
        XCTAssertEqual(word.content, WordContent.empty)
    }

    func testCorruptChatDataFallsBackToEmptyChat() {
        let word = Word(spanish: "hablar", key: "hablar", searchKey: "hablar", content: .empty, rawJSON: Data())
        word.chatData = Data("not valid json".utf8)
        XCTAssertTrue(word.chat.isEmpty)
    }

    func testContentSetterUpdatesDenormalizedFields() {
        let word = Word(spanish: "hablar", key: "hablar", searchKey: "hablar", content: .empty, rawJSON: Data())
        var content = WordContent.empty
        content.meaning.translations = ["to speak"]
        content.forms.partOfSpeech = "verb"
        word.content = content
        XCTAssertEqual(word.translation, "to speak")
        XCTAssertEqual(word.partOfSpeech, "verb")
    }
}
