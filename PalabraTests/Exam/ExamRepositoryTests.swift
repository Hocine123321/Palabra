import XCTest
@testable import Palabra

@MainActor
final class ExamRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var repo: SwiftDataExamRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataExamRepository.inMemory()
    }

    private func record(_ word: UUID, _ score: Double, kind: ExamQuestionKind = .typeSpanish, headword: String = "hablar", involved: [UUID]? = nil) -> ExamAnswerRecord {
        ExamAnswerRecord(id: UUID(), wordID: word, involvedWordIDs: involved, headword: headword, kindRaw: kind.rawValue, score: score, given: "x", expected: "y")
    }

    @discardableResult
    private func save(_ records: [ExamAnswerRecord], at offset: TimeInterval = 0, config: ExamConfig = ExamConfig()) throws -> ExamResult {
        try XCTUnwrap(repo.save(config: config, records: records, duration: 42, now: t0.addingTimeInterval(offset)))
    }

    func testSavingKeepsTheScoreTheConfigAndTheAnswers() throws {
        var config = ExamConfig()
        config.source = .section("Food")
        config.skills = [.typing]
        let word = UUID()
        let saved = try save([record(word, 1), record(word, 0.5)], config: config)
        XCTAssertEqual(saved.questionCount, 2)
        XCTAssertEqual(saved.fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(saved.durationSeconds, 42)
        XCTAssertEqual(saved.config, config)
        XCTAssertEqual(saved.records.map(\.score), [1, 0.5])
        XCTAssertEqual(repo.result(id: saved.id)?.id, saved.id)
    }

    func testAnExamWithNoAnswersIsNotSaved() {
        XCTAssertNil(repo.save(config: ExamConfig(), records: [], duration: 3, now: t0))
        XCTAssertTrue(repo.recent(limit: 10).isEmpty)
    }

    func testRecentIsNewestFirstAndLimited() throws {
        let word = UUID()
        try save([record(word, 1)], at: 0)
        try save([record(word, 0)], at: 100)
        try save([record(word, 0.5)], at: 50)
        XCTAssertEqual(repo.recent(limit: 10).map(\.scoreSum), [0, 0.5, 1])
        XCTAssertEqual(repo.recent(limit: 2).count, 2)
    }

    func testOnlyTheLatestHundredExamsAreKept() throws {
        let word = UUID()
        for index in 0..<(SwiftDataExamRepository.maxResults + 5) { try save([record(word, 1)], at: TimeInterval(index)) }
        let kept = repo.recent(limit: 1_000)
        XCTAssertEqual(kept.count, SwiftDataExamRepository.maxResults)
        XCTAssertEqual(kept.last?.createdAt, t0.addingTimeInterval(5), "the oldest were dropped")
    }

    func testDeleteOneAndDeleteAll() throws {
        let word = UUID()
        let first = try save([record(word, 1)], at: 0)
        try save([record(word, 1)], at: 1)
        repo.delete(id: first.id)
        XCTAssertEqual(repo.recent(limit: 10).count, 1)
        XCTAssertNil(repo.result(id: first.id))
        repo.deleteAll()
        XCTAssertTrue(repo.recent(limit: 10).isEmpty)
    }

    func testWordStatsAddUpAccuracyAcrossExams() throws {
        let hablar = UUID(), comer = UUID()
        try save([record(hablar, 1), record(comer, 0)], at: 0)
        try save([record(hablar, 0.5)], at: 10)
        let stats = repo.wordStats(lastExams: 10)
        XCTAssertEqual(stats[hablar]?.attempts, 2)
        XCTAssertEqual(stats[hablar]?.accuracy ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(stats[comer]?.accuracy, 0)
        XCTAssertEqual(stats[hablar]?.lastSeen, t0.addingTimeInterval(10))
    }

    func testWordStatsOnlyLookAtTheLastFewExams() throws {
        let word = UUID()
        try save([record(word, 0)], at: 0)
        try save([record(word, 1)], at: 10)
        let stats = repo.wordStats(lastExams: 1)
        XCTAssertEqual(stats[word]?.attempts, 1)
        XCTAssertEqual(stats[word]?.accuracy, 1)
    }

    func testAMatchingQuestionCountsForEveryWordInIt() throws {
        let a = UUID(), b = UUID(), c = UUID()
        try save([record(a, 0.5, kind: .matchPairs, involved: [a, b, c])])
        let stats = repo.wordStats(lastExams: 5)
        XCTAssertEqual(Set(stats.keys), [a, b, c])
        XCTAssertEqual(stats[b]?.accuracy, 0.5)
    }

    // MARK: - Backup

    func testBackupAndRestoreMoveExamsToAnotherLibraryOnce() throws {
        let word = UUID(), newWord = UUID()
        let saved = try save([record(word, 1), record(word, 0, involved: [word, UUID()])], at: 5)
        let backup = repo.backup()
        XCTAssertEqual(backup.map(\.id), [saved.id])

        let other = SwiftDataExamRepository.inMemory()
        XCTAssertEqual(try other.restore(backup, wordIDMap: [word: newWord]), 1)
        let restored = try XCTUnwrap(other.result(id: saved.id))
        XCTAssertEqual(restored.records.map(\.wordID), [newWord, newWord], "answers point at the words' ids in this library")
        XCTAssertEqual(restored.records[1].involvedWordIDs?.first, newWord)
        XCTAssertEqual(restored.createdAt, saved.createdAt)
        XCTAssertEqual(restored.scoreSum, saved.scoreSum)

        XCTAssertEqual(try other.restore(backup, wordIDMap: [:]), 0, "importing the same file again adds nothing")
        XCTAssertEqual(other.recent(limit: 10).count, 1)
    }

    func testRestoreIgnoresAnImpossibleScoreAndRepeatedIDsInTheFile() throws {
        let word = UUID()
        let saved = try save([record(word, 1)])
        var entry = repo.backup()[0]
        entry.scoreSum = 500
        let other = SwiftDataExamRepository.inMemory()
        XCTAssertEqual(try other.restore([entry, entry], wordIDMap: [:]), 1)
        XCTAssertEqual(other.result(id: saved.id)?.scoreSum, 1, "never more than one point a question")
    }

    func testARecordWrittenByAnEarlierVersionStillDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString)","wordID":"\#(UUID().uuidString)","headword":"hablar","kindRaw":"typeSpanish","score":1,"given":"a","expected":"b"}"#
        let record = try JSONDecoder().decode(ExamAnswerRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.involvedWordIDs)
        XCTAssertNil(record.feedback)
        XCTAssertEqual(record.words, [record.wordID])
        XCTAssertEqual(record.kind, .typeSpanish)
    }
}
