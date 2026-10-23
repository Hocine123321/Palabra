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

    func testExportThenImportIntoFreshLibrarySkipsExistingOnSecondImport() throws {
        repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        let exported = try repository.exportData()

        let freshContainer = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let freshRepository = SwiftDataWordRepository(context: ModelContext(freshContainer))

        let firstImport = try! freshRepository.importData(exported)
        XCTAssertEqual(firstImport, ImportResult(imported: 1, skipped: 0))

        let secondImport = try! freshRepository.importData(exported)
        XCTAssertEqual(secondImport, ImportResult(imported: 0, skipped: 1))
        XCTAssertEqual(freshRepository.allWords().count, 1)
    }

    func testFlushIsTrueWhenNothingIsPendingAndAfterAWrite() {
        XCTAssertTrue(repository.flush())
        repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        XCTAssertTrue(repository.flush())
    }

    func testWordByIdAndWordCountDoNotNeedTheWholeLibrary() {
        XCTAssertEqual(repository.wordCount(), 0)
        let a = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        repository.insert(spanish: "comer", key: "comer", searchKey: "comer", content: sampleContent(word: "comer"), rawJSON: Data())
        XCTAssertEqual(repository.wordCount(), 2)
        XCTAssertEqual(repository.word(id: a.id)?.key, "hablar")
        XCTAssertNil(repository.word(id: UUID()))
    }

    func testWordSummariesCarryTheLightFieldsNewestFirst() {
        let first = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        first.createdAt = Date(timeIntervalSince1970: 1_000)
        let second = repository.insert(spanish: "comer", key: "comer", searchKey: "comer", content: sampleContent(word: "comer"), rawJSON: Data())
        second.createdAt = Date(timeIntervalSince1970: 2_000)
        repository.updatePlacement(id: first.id, category: "Verbs", tags: [])
        let summaries = repository.wordSummaries()
        XCTAssertEqual(summaries.map(\.spanish), ["comer", "hablar"])
        XCTAssertEqual(summaries.last, WordSummary(id: first.id, spanish: "hablar", translation: "to speak", category: "Verbs"))
        XCTAssertNil(summaries.first?.category)
    }

    func testImportSkipsEntriesWithABlankHeadword() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            VocabularyLibraryExporter.Item(content: sampleContent(word: "   "), raw: Data(), createdAt: now, updatedAt: now, chat: []),
            VocabularyLibraryExporter.Item(content: sampleContent(word: "hablar"), raw: Data(), createdAt: now, updatedAt: now, chat: [])
        ]
        let result = try repository.importData(VocabularyLibraryExporter.encode(items: items))
        XCTAssertEqual(result, ImportResult(imported: 1, skipped: 1))
        XCTAssertEqual(repository.allWords().map(\.key), ["hablar"])
    }

    func testImportClipsHugeTextInsteadOfRejectingTheWord() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var content = sampleContent(word: "hablar")
        content.meaning.explanation = String(repeating: "x", count: 50_000)
        content.meaning.translations = (0..<80).map { "t\($0)" }
        content.similarWords = (0..<40).map { .init(word: "w\($0)", difference: "d") }
        let item = VocabularyLibraryExporter.Item(content: content, raw: Data(), createdAt: now, updatedAt: now, chat: [])
        let result = try repository.importData(VocabularyLibraryExporter.encode(items: [item]))
        XCTAssertEqual(result, ImportResult(imported: 1, skipped: 0))
        let stored = try XCTUnwrap(repository.find(key: "hablar")).content
        XCTAssertEqual(stored.meaning.explanation.count, ContentValidator.maxParagraphLength)
        XCTAssertEqual(stored.meaning.translations.count, ContentValidator.maxTranslations)
        XCTAssertEqual(stored.similarWords.count, 8)
    }

    func testImportKeepsAWordWhoseShapeIsUnusual() throws {
        // An old export with two examples must still come in (validate() would reject it).
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var content = sampleContent(word: "hablar")
        content.examples = Array(content.examples.prefix(2))
        let item = VocabularyLibraryExporter.Item(content: content, raw: Data(), createdAt: now, updatedAt: now, chat: [])
        let result = try repository.importData(VocabularyLibraryExporter.encode(items: [item]))
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(repository.find(key: "hablar")?.content.examples.count, 2)
    }

    func testUpdatePronunciationStoresAndClearsAudio() {
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        XCTAssertNil(repository.find(key: "hablar")?.pronunciationAudio)

        let audio = Data([1, 2, 3, 4])
        repository.updatePronunciation(id: word.id, audio: audio)
        XCTAssertEqual(repository.find(key: "hablar")?.pronunciationAudio, audio)

        repository.updatePronunciation(id: word.id, audio: nil)
        XCTAssertNil(repository.find(key: "hablar")?.pronunciationAudio)
    }

    func testReplaceContentClearsStalePronunciationAudio() {
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        repository.updatePronunciation(id: word.id, audio: Data([9, 9, 9]))

        repository.replaceContent(id: word.id, content: sampleContent(word: "hablar (regenerated)"), rawJSON: Data("new".utf8))

        XCTAssertNil(repository.find(key: "hablar")?.pronunciationAudio)
    }
}
