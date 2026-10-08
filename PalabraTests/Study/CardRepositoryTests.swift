import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class CardRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataCardRepository!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Deck.self, Card.self, ReviewLog.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        repository = SwiftDataCardRepository(context: ModelContext(container))
    }

    private func entry(_ front: String, _ back: String) -> VocabularyCardEntry {
        VocabularyCardEntry(wordID: UUID(), front: front, back: back)
    }

    private func entry(_ id: UUID, _ front: String, _ back: String) -> VocabularyCardEntry {
        VocabularyCardEntry(wordID: id, front: front, back: back)
    }

    private func drafts(_ count: Int) -> [CardDraft] {
        (0..<count).map { CardDraft(front: "front \($0)", back: "back \($0)") }
    }

    private func logs() -> [ReviewLog] {
        (try? ModelContext(container).fetch(FetchDescriptor<ReviewLog>())) ?? []
    }

    // MARK: - Vocabulary mirror

    func testSyncCreatesVocabularyDeckAndOneCardPerWord() {
        repository.syncVocabulary([entry("hablar", "to speak"), entry("comer", "to eat")])
        let decks = repository.decks()
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.kind, .vocabulary)
        let cards = repository.cards(inDeck: decks[0].id)
        XCTAssertEqual(Set(cards.map(\.front)), ["hablar", "comer"])
        XCTAssertTrue(cards.allSatisfy { $0.sourceWordID != nil && $0.phase == .new })
    }

    func testSyncIsIdempotent() {
        let a = UUID(), b = UUID()
        let entries = [entry(a, "hablar", "to speak"), entry(b, "comer", "to eat")]
        repository.syncVocabulary(entries)
        repository.syncVocabulary(entries)
        repository.syncVocabulary(entries)
        XCTAssertEqual(repository.decks().count, 1)
        XCTAssertEqual(repository.cards(inDeck: repository.decks()[0].id).count, 2)
    }

    func testSyncUpdatesTextButKeepsSchedulingState() {
        let id = UUID()
        repository.syncVocabulary([entry(id, "hablar", "to speak")])
        let deckID = repository.decks()[0].id
        let cardID = repository.cards(inDeck: deckID)[0].id
        repository.record(cardID: cardID, grade: .good, now: now)

        repository.syncVocabulary([entry(id, "hablar", "to talk")])
        let card = repository.cards(inDeck: deckID)[0]
        XCTAssertEqual(card.back, "to talk")
        XCTAssertEqual(card.phase, .review)
        XCTAssertEqual(card.id, cardID)
    }

    func testSyncRemovesCardsAndLogsForDeletedWords() {
        let a = UUID(), b = UUID()
        repository.syncVocabulary([entry(a, "hablar", "to speak"), entry(b, "comer", "to eat")])
        let deckID = repository.decks()[0].id
        let cardA = repository.cards(inDeck: deckID).first { $0.sourceWordID == a }!
        repository.record(cardID: cardA.id, grade: .good, now: now)
        XCTAssertEqual(logs().count, 1)

        repository.syncVocabulary([entry(b, "comer", "to eat")])
        XCTAssertEqual(repository.cards(inDeck: deckID).map(\.front), ["comer"])
        XCTAssertEqual(logs().count, 0)
    }

    func testSyncWithNoWordsAndNoDeckCreatesNothing() {
        repository.syncVocabulary([])
        XCTAssertTrue(repository.decks().isEmpty)
    }

    // MARK: - Decks

    func testCreateDeckSkipsBlankDrafts() {
        let deck = repository.createDeck(name: "Bio", drafts: [CardDraft(front: "a", back: "b"), CardDraft(front: " ", back: "x"), CardDraft(front: "c", back: "")], now: now)
        XCTAssertEqual(deck.kind, .user)
        XCTAssertEqual(repository.cards(inDeck: deck.id).count, 1)
    }

    func testDeleteDeckRemovesItsCardsAndLogs() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(2), now: now)
        let cardID = repository.cards(inDeck: deck.id)[0].id
        repository.record(cardID: cardID, grade: .good, now: now)
        let other = repository.createDeck(name: "Chem", drafts: drafts(1), now: now)

        repository.deleteDeck(id: deck.id)
        XCTAssertEqual(repository.decks().map(\.id), [other.id])
        XCTAssertTrue(repository.cards(inDeck: deck.id).isEmpty)
        XCTAssertEqual(repository.cards(inDeck: other.id).count, 1)
        XCTAssertTrue(logs().isEmpty)
    }

    func testVocabularyDeckListedFirst() {
        _ = repository.createDeck(name: "Bio", drafts: drafts(1), now: now.addingTimeInterval(-1000))
        repository.syncVocabulary([entry("hablar", "to speak")])
        XCTAssertEqual(repository.decks().first?.kind, .vocabulary)
    }

    // MARK: - Reviewing

    func testRecordUpdatesCardAndWritesLog() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(1), now: now)
        let cardID = repository.cards(inDeck: deck.id)[0].id
        let state = repository.record(cardID: cardID, grade: .good, now: now)
        XCTAssertEqual(state?.phase, .review)
        let card = repository.cards(inDeck: deck.id)[0]
        XCTAssertEqual(card.phase, .review)
        XCTAssertEqual(card.interval, 1)
        let written = logs()
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.cardID, cardID)
        XCTAssertEqual(written.first?.grade, .good)
        XCTAssertEqual(written.first?.newInterval, 1)
    }

    func testRecordUnknownCardReturnsNil() {
        XCTAssertNil(repository.record(cardID: UUID(), grade: .good, now: now))
    }

    func testCountsSplitNewAndDue() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(3), now: now)
        let first = repository.cards(inDeck: deck.id)[0].id
        repository.record(cardID: first, grade: .again, now: now) // learning, due in 10 minutes
        XCTAssertEqual(repository.counts(now: now)[deck.id], DeckCounts(total: 3, due: 0, new: 2))
        XCTAssertEqual(repository.counts(now: now.addingTimeInterval(700))[deck.id], DeckCounts(total: 3, due: 1, new: 2))
    }

    func testStudyQueuePutsDueCardsBeforeNewOnes() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(3), now: now)
        let first = repository.cards(inDeck: deck.id)[0].id
        repository.record(cardID: first, grade: .again, now: now)
        let queue = repository.studyQueue(deckID: nil, now: now.addingTimeInterval(700), newLimit: 20)
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.first?.id, first)
    }

    func testStudyQueueRespectsNewLimit() {
        _ = repository.createDeck(name: "Bio", drafts: drafts(5), now: now)
        XCTAssertEqual(repository.studyQueue(deckID: nil, now: now, newLimit: 2).count, 2)
        XCTAssertEqual(repository.studyQueue(deckID: nil, now: now, newLimit: 0).count, 0)
    }

    func testNewLimitIsSpentByCardsFirstStudiedToday() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(3), now: now)
        let first = repository.cards(inDeck: deck.id)[0].id
        repository.record(cardID: first, grade: .good, now: now) // due tomorrow, so not in the queue
        let queue = repository.studyQueue(deckID: nil, now: now, newLimit: 2)
        XCTAssertEqual(queue.count, 1) // 2 allowed - 1 already introduced today
        XCTAssertFalse(queue.contains { $0.id == first })
    }

    func testReviewedCardReturnsWhenDue() {
        let deck = repository.createDeck(name: "Bio", drafts: drafts(1), now: now)
        let id = repository.cards(inDeck: deck.id)[0].id
        repository.record(cardID: id, grade: .good, now: now)
        XCTAssertTrue(repository.studyQueue(deckID: nil, now: now, newLimit: 20).isEmpty)
        let later = repository.studyQueue(deckID: nil, now: now.addingTimeInterval(2 * 86_400), newLimit: 0)
        XCTAssertEqual(later.map(\.id), [id])
    }

    func testStudyQueueCanBeLimitedToOneDeck() {
        let a = repository.createDeck(name: "A", drafts: drafts(2), now: now)
        _ = repository.createDeck(name: "B", drafts: drafts(3), now: now)
        XCTAssertEqual(repository.studyQueue(deckID: a.id, now: now, newLimit: 20).count, 2)
        XCTAssertEqual(repository.studyQueue(deckID: nil, now: now, newLimit: 20).count, 5)
    }
}

@MainActor
final class CardRepositoryAddCardsTests: XCTestCase {
    func testAddCardsSkipsBlanksAndDuplicatesAndProtectsTheVocabularyDeck() {
        let repo = SwiftDataCardRepository.inMemory()
        let deck = repo.createDeck(name: "Food", drafts: [CardDraft(front: "pan", back: "bread")], now: Date())
        let added = repo.addCards(toDeck: deck.id, drafts: [
            CardDraft(front: "PAN", back: "Bread"), CardDraft(front: " ", back: "x"), CardDraft(front: "agua", back: "water"), CardDraft(front: "agua", back: "water"),
        ], now: Date())
        XCTAssertEqual(added, 1)
        XCTAssertEqual(repo.cards(inDeck: deck.id).count, 2)

        repo.syncVocabulary([VocabularyCardEntry(wordID: UUID(), front: "hola", back: "hello")])
        let vocabulary = repo.decks().first { $0.kind == .vocabulary }!
        XCTAssertEqual(repo.addCards(toDeck: vocabulary.id, drafts: [CardDraft(front: "a", back: "b")], now: Date()), 0)
        XCTAssertEqual(repo.addCards(toDeck: UUID(), drafts: [CardDraft(front: "a", back: "b")], now: Date()), 0)
    }
}
