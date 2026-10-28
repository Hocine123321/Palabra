import XCTest
import SwiftData
@testable import Palabra

/// The seam between the library (`Word`) and the exam (`ExamWord`): mapping, and what an exam writes back.
@MainActor
final class ExamEnvironmentTests: XCTestCase {
    private var words: SwiftDataWordRepository!
    private var review: SwiftDataReviewRepository!
    private var env: AppEnvironment!

    override func setUpWithError() throws {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        words = SwiftDataWordRepository(context: ModelContext(container))
        review = SwiftDataReviewRepository.inMemory()
        env = AppEnvironment(
            ai: MockAIClient(),
            repository: words,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(account: "exam-env-\(UUID().uuidString)"),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "exam-env-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            reviewRepository: review
        )
    }

    private func add(_ spanish: String) -> Word {
        words.insert(spanish: spanish, key: spanish, searchKey: spanish, content: StubAIClient.sampleContent(for: spanish), rawJSON: Data())
    }

    private func record(_ word: UUID, score: Double, given: String = "x", expected: String = "y", kind: ExamQuestionKind = .typeSpanish) -> ExamAnswerRecord {
        ExamAnswerRecord(id: UUID(), wordID: word, headword: "h", kindRaw: kind.rawValue, score: score, given: given, expected: expected)
    }

    func testWordsBecomeExamWordsWithTheirContentAndReviewFlag() {
        let hola = add("hola")
        let adios = add("adios")
        review.flag([ReviewFlag(wordID: adios.id, headword: "adios", translation: "", score: 0.5, note: "", sourceArtifactID: nil)], now: Date())
        let exam = env.examWords()
        XCTAssertEqual(Set(exam.map(\.headword)), ["hola", "adios"])
        let mapped = exam.first { $0.id == hola.id }
        XCTAssertEqual(mapped?.translations, ["(sample translation)"])
        XCTAssertEqual(mapped?.examples.count, 3)
        XCTAssertEqual(mapped?.needsReview, false)
        XCTAssertEqual(exam.first { $0.id == adios.id }?.needsReview, true)
    }

    func testFlaggingKeepsTheWorstAnswerPerWordWithWhatWasTyped() throws {
        let hola = add("hola")
        let flagged = env.flagExamMisses([
            record(hola.id, score: 0.75, given: "ola", expected: "hola"),
            record(hola.id, score: 0, given: "hla", expected: "hola"),
            record(hola.id, score: 1, given: "hola", expected: "hola"),
        ])
        XCTAssertEqual(flagged, 1)
        let need = try XCTUnwrap(review.openNeed(wordID: hola.id))
        XCTAssertEqual(need.note, "hla → hola")
        XCTAssertEqual(need.score, 1, accuracy: 0.001)
    }

    func testFlaggingLeavesCorrectAnswersAndDeletedWordsAlone() {
        let keep = add("hola")
        let gone = add("adios")
        words.delete(id: gone.id)
        let flagged = env.flagExamMisses([record(keep.id, score: 1), record(gone.id, score: 0)])
        XCTAssertEqual(flagged, 0)
        XCTAssertTrue(review.openNeeds().isEmpty)
    }

    func testAMatchingMissFlagsEveryWordInItWithoutANote() throws {
        let a = add("hola")
        let b = add("adios")
        var match = record(a.id, score: 0.5, kind: .matchPairs)
        match.involvedWordIDs = [a.id, b.id]
        XCTAssertEqual(env.flagExamMisses([match]), 2)
        XCTAssertEqual(try XCTUnwrap(review.openNeed(wordID: b.id)).note, "")
    }
}
