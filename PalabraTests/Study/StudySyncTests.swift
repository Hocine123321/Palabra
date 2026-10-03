import XCTest
import SwiftData
@testable import Palabra

/// The Word -> card mirror lives in `AppEnvironment.syncVocabularyCards`.
@MainActor
final class StudySyncTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            ai: StubAIClient(),
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "study-\(UUID().uuidString)") ?? .standard)
        )
    }

    @discardableResult
    private func addWord(_ env: AppEnvironment, _ text: String) -> Word {
        env.repository.insert(spanish: text, key: WordKey.identity(text), searchKey: WordKey.search(text), content: StubAIClient.sampleContent(for: text), rawJSON: Data())
    }

    func testEveryLibraryWordBecomesOneBasicCard() {
        let env = makeEnvironment()
        let hablar = addWord(env, "hablar")
        addWord(env, "comer")
        env.syncVocabularyCards()

        let decks = env.cards.decks()
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks[0].kind, .vocabulary)
        let cards = env.cards.cards(inDeck: decks[0].id)
        XCTAssertEqual(Set(cards.map(\.front)), ["hablar", "comer"])
        XCTAssertTrue(cards.allSatisfy { $0.back == "(sample translation)" })
        XCTAssertEqual(cards.first { $0.front == "hablar" }?.sourceWordID, hablar.id)
    }

    func testSyncingTwiceDoesNotDuplicate() {
        let env = makeEnvironment()
        addWord(env, "hablar")
        env.syncVocabularyCards()
        env.syncVocabularyCards()
        XCTAssertEqual(env.cards.cards(inDeck: env.cards.decks()[0].id).count, 1)
    }

    func testDeletingAWordRemovesItsCardOnNextSync() {
        let env = makeEnvironment()
        let hablar = addWord(env, "hablar")
        addWord(env, "comer")
        env.syncVocabularyCards()

        env.repository.delete(id: hablar.id)
        env.syncVocabularyCards()
        XCTAssertEqual(env.cards.cards(inDeck: env.cards.decks()[0].id).map(\.front), ["comer"])
    }

    func testNewCardsPerDayDefaultsToTwentyAndPersists() {
        let suite = "study-\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        XCTAssertEqual(settings.newCardsPerDay, 20)
        settings.newCardsPerDay = 35
        XCTAssertEqual(SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard).newCardsPerDay, 35)
        settings.newCardsPerDay = -5
        XCTAssertEqual(settings.newCardsPerDay, 0)
    }
}
