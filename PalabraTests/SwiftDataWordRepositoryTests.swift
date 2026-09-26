import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class SwiftDataWordRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataWordRepository!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [config])
        repository = SwiftDataWordRepository(context: ModelContext(container))
    }

    private func sampleContent(word: String = "hablar") -> WordContent {
        WordContent(
            word: word,
            examples: [
                .init(context: "a", spanish: "uno", english: "one"),
                .init(context: "b", spanish: "dos", english: "two"),
                .init(context: "c", spanish: "tres", english: "three")
            ],
            meaning: .init(translations: ["to speak"], explanation: "explanation"),
            usage: .init(explanation: "usage", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: "hablo", note: nil)])]),
            similarWords: [.init(word: "conversar", difference: "more formal")]
        )
    }

    func testInsertThenFindByKey() {
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        XCTAssertEqual(repository.find(key: "hablar")?.id, word.id)
    }

    func testReplaceContentPreservesIDCreatedAtAndChat() {
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        repository.updateChat(id: word.id, messages: [ChatMessage(role: .user, text: "hola")])
        let originalCreatedAt = word.createdAt

        repository.replaceContent(id: word.id, content: sampleContent(word: "hablar (regenerated)"), rawJSON: Data("new".utf8))

        let updated = repository.find(key: "hablar")
        XCTAssertEqual(updated?.id, word.id)
        XCTAssertEqual(updated?.createdAt, originalCreatedAt)
        XCTAssertEqual(updated?.chat.count, 1)
        XCTAssertEqual(updated?.content.word, "hablar (regenerated)")
    }

    func testDeleteRemovesWord() {
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        repository.delete(id: word.id)
        XCTAssertNil(repository.find(key: "hablar"))
    }

    func testDeleteAllRemovesEveryWord() {
        repository.insert(spanish: "uno", key: "uno", searchKey: "uno", content: sampleContent(word: "uno"), rawJSON: Data())
        repository.insert(spanish: "dos", key: "dos", searchKey: "dos", content: sampleContent(word: "dos"), rawJSON: Data())
        repository.deleteAll()
        XCTAssertTrue(repository.allWords().isEmpty)
    }

    func testExportThenImportIntoFreshLibrarySkipsExistingOnSecondImport() {
        repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        let exported = repository.exportData()

        let freshContainer = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let freshRepository = SwiftDataWordRepository(context: ModelContext(freshContainer))

        let firstImport = try! freshRepository.importData(exported)
        XCTAssertEqual(firstImport, ImportResult(imported: 1, skipped: 0))

        let secondImport = try! freshRepository.importData(exported)
        XCTAssertEqual(secondImport, ImportResult(imported: 0, skipped: 1))
        XCTAssertEqual(freshRepository.allWords().count, 1)
    }
}
