import XCTest
@testable import Palabra

@MainActor
final class ReviewViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var repository: SwiftDataCardRepository!

    override func setUp() {
        super.setUp()
        repository = SwiftDataCardRepository.inMemory()
    }

    private func makeModel(cards: Int) -> ReviewViewModel {
        let drafts = (0..<cards).map { CardDraft(front: "f\($0)", back: "b\($0)") }
        let deck = repository.createDeck(name: "Deck", drafts: drafts, now: now)
        let queue = repository.studyQueue(deckID: deck.id, now: now, newLimit: 20)
        let moment = now
        return ReviewViewModel(queue: queue, repository: repository, now: { moment })
    }

    func testGradingBeforeFlipIsIgnored() {
        let model = makeModel(cards: 2)
        model.grade(.good)
        XCTAssertEqual(model.remaining, 2)
        XCTAssertEqual(model.answered, 0)
    }

    func testGoodRemovesCardAndResetsFlip() {
        let model = makeModel(cards: 2)
        model.flip()
        model.grade(.good)
        XCTAssertEqual(model.remaining, 1)
        XCTAssertEqual(model.answered, 1)
        XCTAssertFalse(model.isFlipped)
    }

    func testAgainPutsTheCardBackAtTheEndOfTheQueue() {
        let model = makeModel(cards: 2)
        let firstID = model.current!.id
        model.flip()
        model.grade(.again)
        XCTAssertEqual(model.remaining, 2)
        XCTAssertNotEqual(model.current?.id, firstID)
        XCTAssertEqual(model.queue.last?.id, firstID)
    }

    func testSessionFinishesAfterEveryCardIsGood() {
        let model = makeModel(cards: 3)
        for _ in 0..<3 {
            model.flip()
            model.grade(.good)
        }
        XCTAssertTrue(model.isFinished)
        XCTAssertNil(model.current)
        XCTAssertEqual(model.answered, 3)
    }

    func testGradeIsPersistedThroughTheRepository() {
        let model = makeModel(cards: 1)
        model.flip()
        model.grade(.easy)
        XCTAssertEqual(repository.counts(now: now).values.first?.new, 0)
    }
}
