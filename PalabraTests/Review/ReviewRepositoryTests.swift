import XCTest
@testable import Palabra

@MainActor
final class ReviewRepositoryTests: XCTestCase {
    private var repo: SwiftDataReviewRepository!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() { repo = SwiftDataReviewRepository.inMemory() }

    private func flag(_ id: UUID, headword: String = "hola", score: Double = 0.5, note: String = "", source: UUID? = nil, at offset: TimeInterval = 0) {
        repo.flag([ReviewFlag(wordID: id, headword: headword, translation: "hello", score: score, note: note, sourceArtifactID: source)], now: t0.addingTimeInterval(offset))
    }

    func testFlagCreatesAnOpenNeedWithSnapshots() throws {
        let id = UUID(), source = UUID()
        flag(id, note: "mixed up", source: source)
        let need = try XCTUnwrap(repo.openNeed(wordID: id))
        XCTAssertEqual(need.headword, "hola")
        XCTAssertEqual(need.translation, "hello")
        XCTAssertEqual(need.note, "mixed up")
        XCTAssertEqual(need.sourceArtifactID, source)
        XCTAssertEqual(need.flagCount, 1)
        XCTAssertEqual(need.status, .open)
        XCTAssertEqual(repo.openCount(), 1)
    }

    func testReflagUpsertsKeepingMaxScoreAndRefreshingNote() throws {
        let id = UUID()
        flag(id, score: 0.8, note: "first")
        flag(id, score: 0.3, note: "second", at: 10)
        XCTAssertEqual(repo.openCount(), 1)
        let need = try XCTUnwrap(repo.openNeed(wordID: id))
        XCTAssertEqual(need.flagCount, 2)
        XCTAssertEqual(need.score, 0.8)
        XCTAssertEqual(need.note, "second")
        XCTAssertEqual(need.updatedAt, t0.addingTimeInterval(10))
        flag(id, score: 0.95, at: 20)
        XCTAssertEqual(try XCTUnwrap(repo.openNeed(wordID: id)).score, 0.95)
    }

    func testScoreIsClampedAndNoteIsCapped() throws {
        let a = UUID(), b = UUID(), c = UUID()
        flag(a, score: 7)
        flag(b, score: -3)
        flag(c, score: .nan, note: String(repeating: "x", count: 500))
        XCTAssertEqual(try XCTUnwrap(repo.openNeed(wordID: a)).score, 1)
        XCTAssertEqual(try XCTUnwrap(repo.openNeed(wordID: b)).score, 0)
        let capped = try XCTUnwrap(repo.openNeed(wordID: c))
        XCTAssertEqual(capped.score, 0.5)
        XCTAssertEqual(capped.note.count, ReviewLimits.maxNoteLength)
    }

    func testOpenNeedsSortByScoreThenRecency() {
        let low = UUID(), highOld = UUID(), highNew = UUID()
        flag(low, headword: "low", score: 0.2, at: 30)
        flag(highOld, headword: "highOld", score: 0.9, at: 10)
        flag(highNew, headword: "highNew", score: 0.9, at: 20)
        XCTAssertEqual(repo.openNeeds().map(\.headword), ["highNew", "highOld", "low"])
    }

    func testMarkLearnedClearsAndKeepsHistory() throws {
        let id = UUID()
        flag(id)
        let need = try XCTUnwrap(repo.openNeed(wordID: id))
        repo.markLearned(id: need.id, now: t0.addingTimeInterval(5))
        XCTAssertNil(repo.openNeed(wordID: id))
        XCTAssertEqual(repo.openCount(), 0)
        XCTAssertEqual(need.status, .cleared)
        XCTAssertEqual(need.clearedAt, t0.addingTimeInterval(5))
    }

    func testFlagAfterLearnedStartsAFreshOpenNeed() throws {
        let id = UUID()
        flag(id, score: 0.9)
        repo.markLearned(id: try XCTUnwrap(repo.openNeed(wordID: id)).id, now: t0)
        flag(id, score: 0.4, at: 50)
        let fresh = try XCTUnwrap(repo.openNeed(wordID: id))
        XCTAssertEqual(fresh.flagCount, 1)
        XCTAssertEqual(fresh.score, 0.4)
    }

    func testDeleteOrphansRemovesNeedsOfMissingWords() {
        let keep = UUID(), gone = UUID(), goneLearned = UUID()
        flag(keep)
        flag(gone)
        flag(goneLearned)
        if let need = repo.openNeed(wordID: goneLearned) { repo.markLearned(id: need.id, now: t0) }
        repo.deleteOrphans(validWordIDs: [keep])
        XCTAssertEqual(repo.openNeeds().map(\.wordID), [keep])
        XCTAssertNil(repo.openNeed(wordID: gone))
    }
}
