import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class SwiftDataFlashcardRepositoryTests: XCTestCase {
    private func makeRepository() -> SwiftDataFlashcardRepository {
        let schema = Schema([Flashcard.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataFlashcardRepository(context: ModelContext(container))
    }

    func testInsertCreatesADueCard() {
        let repo = makeRepository()
        let card = repo.insert(subject: "Biology", front: "What is a cell?", back: "The basic unit of life.", hint: nil)
        XCTAssertTrue(card.isDue())
        XCTAssertEqual(repo.dueCards(subject: "Biology", now: Date()).count, 1)
    }

    func testReviewWithGoodPushesCardOutOfDueList() {
        let repo = makeRepository()
        let card = repo.insert(subject: "Biology", front: "Q", back: "A", hint: nil)
        repo.review(id: card.id, grade: .good, now: Date())
        XCTAssertTrue(repo.dueCards(subject: "Biology", now: Date()).isEmpty)
    }

    func testSubjectsListsDistinctSubjects() {
        let repo = makeRepository()
        repo.insert(subject: "Biology", front: "Q1", back: "A1", hint: nil)
        repo.insert(subject: "Biology", front: "Q2", back: "A2", hint: nil)
        repo.insert(subject: "History", front: "Q3", back: "A3", hint: nil)
        XCTAssertEqual(repo.subjects(), ["Biology", "History"])
    }

    func testDeleteRemovesCard() {
        let repo = makeRepository()
        let card = repo.insert(subject: "Biology", front: "Q", back: "A", hint: nil)
        repo.delete(id: card.id)
        XCTAssertTrue(repo.allCards().isEmpty)
    }
}
