import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class ReviewSyncTests: XCTestCase {
    func testSyncDropsNeedsOfDeletedWords() throws {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let words = SwiftDataWordRepository(context: ModelContext(container))
        let review = SwiftDataReviewRepository.inMemory()
        let keep = words.insert(spanish: "hola", key: "hola", searchKey: "hola", content: StubAIClient.sampleContent(for: "hola"), rawJSON: Data())
        let gone = words.insert(spanish: "adios", key: "adios", searchKey: "adios", content: StubAIClient.sampleContent(for: "adios"), rawJSON: Data())
        review.flag([
            ReviewFlag(wordID: keep.id, headword: "hola", translation: "", score: 0.5, note: "", sourceArtifactID: nil),
            ReviewFlag(wordID: gone.id, headword: "adios", translation: "", score: 0.5, note: "", sourceArtifactID: nil),
        ], now: Date())
        words.delete(id: gone.id)

        let env = AppEnvironment(
            ai: MockAIClient(),
            repository: words,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "review-sync-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            reviewRepository: review
        )
        env.syncReviewNeeds()
        XCTAssertEqual(review.openNeeds().map(\.wordID), [keep.id])
    }
}
