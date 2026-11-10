import SwiftData
import XCTest
@testable import Palabra

@MainActor
final class MirrorStudyRecordsTests: XCTestCase {
    private var cards: SwiftDataCardRepository!
    private var review: SwiftDataReviewRepository!
    private var env: AppEnvironment!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let markup = "<img src=x onerror=1>"

    override func setUpWithError() throws {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        cards = SwiftDataCardRepository.inMemory()
        review = SwiftDataReviewRepository.inMemory()
        env = AppEnvironment(
            ai: MockAIClient(),
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(account: "mirror-study-\(UUID().uuidString)"),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "mirror-study-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            cardRepository: cards,
            reviewRepository: review
        )
    }

    private func collection(_ kind: String) throws -> MirrorCollection {
        try XCTUnwrap(env.mirrorStudyCollections(now: now).first { $0.kind == kind }, kind)
    }

    func testEveryStudyKindIsBuiltEvenWhenEmpty() throws {
        let collections = env.mirrorStudyCollections(now: now)
        XCTAssertEqual(collections.map(\.kind), ["deck", "card", "stats", "review"])
        XCTAssertEqual(try collection("deck").records, [])
        XCTAssertEqual(try collection("card").records, [])
        XCTAssertEqual(try collection("review").records, [])
        XCTAssertEqual(try collection("stats").records.count, 1, "stats is always one record")
    }

    func testDecksCardsStatsAndReviewBecomeRecords() throws {
        cards.syncVocabulary([VocabularyCardEntry(wordID: UUID(), front: "hablar", back: "to speak")])
        let mine = cards.createDeck(name: markup, drafts: [CardDraft(front: "a", back: "b"), CardDraft(front: markup, back: "d")], now: now)
        review.flag([ReviewFlag(wordID: UUID(), headword: "hola", translation: "hello", score: 0.4, note: markup, sourceArtifactID: nil)], now: now)
        review.flag([ReviewFlag(wordID: UUID(), headword: "adios", translation: "bye", score: 0.2, note: "", sourceArtifactID: nil)], now: now)
        let cleared = try XCTUnwrap(review.openNeeds().first { $0.headword == "adios" })
        review.markLearned(id: cleared.id, now: now)

        // decks: one per deck, counts exactly as the repository reports them, the name untouched
        let decks = try collection("deck").records
        XCTAssertEqual(decks.count, 2)
        let counts = cards.counts(now: now)
        let deck = try XCTUnwrap(decks.first { $0.recordID == mine.id.uuidString })
        let payload = try XCTUnwrap(deck.payload.objectValue)
        XCTAssertEqual(Set(payload.keys), ["id", "name", "kind", "createdAt", "counts", "countsAt"])
        XCTAssertEqual(payload["name"]?.stringValue, markup)
        XCTAssertEqual(payload["kind"]?.stringValue, "user")
        XCTAssertEqual(payload["counts"]?["total"], .number(Double(counts[mine.id]?.total ?? -1)))
        XCTAssertEqual(payload["counts"]?["due"], .number(Double(counts[mine.id]?.due ?? -1)))
        XCTAssertEqual(payload["counts"]?["new"], .number(Double(counts[mine.id]?.new ?? -1)))
        XCTAssertEqual(payload["countsAt"]?.stringValue, ISO8601DateFormatter().string(from: now))
        XCTAssertEqual(decks.compactMap { $0.payload["kind"]?.stringValue }.sorted(), ["user", "vocabulary"])

        // cards: only the user deck's two (the vocabulary deck comes from the words), exact keys, no scheduling internals
        let records = try collection("card").records
        XCTAssertEqual(records.count, 2)
        for record in records {
            let card = try XCTUnwrap(record.payload.objectValue)
            XCTAssertEqual(Set(card.keys), ["id", "deckId", "front", "back", "due", "reps", "lapses", "phase", "createdAt"])
            XCTAssertEqual(card["deckId"]?.stringValue, mine.id.uuidString)
            for leaked in ["sourceWordID", "ease", "interval"] { XCTAssertNil(card[leaked], leaked) }
        }
        XCTAssertTrue(records.contains { $0.payload["front"]?.stringValue == markup })

        // stats
        let stats = try XCTUnwrap(try collection("stats").records.first)
        XCTAssertEqual(stats.recordID, "stats")
        XCTAssertEqual(Set(try XCTUnwrap(stats.payload.objectValue).keys), ["reviewedToday", "streak", "lastSevenDays", "asOf"])
        XCTAssertEqual(stats.payload["lastSevenDays"]?.arrayValue?.count, 7)

        // review: the open need only
        let needs = try collection("review").records
        XCTAssertEqual(needs.count, 1)
        let need = try XCTUnwrap(needs[0].payload.objectValue)
        XCTAssertEqual(Set(need.keys), ["id", "wordId", "headword", "translation", "score", "note", "flagCount", "updatedAt"])
        XCTAssertEqual(need["headword"]?.stringValue, "hola")
        XCTAssertEqual(need["note"]?.stringValue, markup)
    }
}
