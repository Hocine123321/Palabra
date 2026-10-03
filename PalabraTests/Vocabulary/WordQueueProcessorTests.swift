import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class WordQueueProcessorTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        keychain = KeychainStore()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    // MARK: helpers

    private func content(word: String) -> WordContent {
        WordContent(
            word: word,
            examples: [
                .init(context: "a", spanish: "uno", english: "one"),
                .init(context: "b", spanish: "dos", english: "two"),
                .init(context: "c", spanish: "tres", english: "three")
            ],
            meaning: .init(translations: ["translation"], explanation: "explanation"),
            usage: .init(explanation: "usage", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: word, note: nil)])]),
            similarWords: [.init(word: "similar", difference: "differs")]
        )
    }

    private func makeEnvironment(connectivity: ConnectivityWaiting = InstantConnectivity()) -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "wqp-\(UUID().uuidString)") ?? .standard),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            connectivity: connectivity
        )
        env.saveAPIKey("test-api-key")
        return (env, client)
    }

    private func selectModel(_ env: AppEnvironment, _ client: MockAIClient) async {
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
    }

    private func waitUntilDone(_ processor: WordQueueProcessor) async {
        for _ in 0..<400 {
            if !processor.isDraining { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: tests

    func testSuccessSavesWordAndRemovesFromQueue() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        client.generateWordResult = .success(content(word: "hablar"))
        env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)

        let processor = WordQueueProcessor(sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertTrue(env.wordQueue.allItems().isEmpty)
        XCTAssertEqual(env.repository.allWords().map(\.spanish), ["hablar"])
    }

    func testRegenerateQueueItemReplacesExistingWord() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        let existing = env.repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(word: "hablar"), rawJSON: Data())
        client.generateWordResult = .success(content(word: "hablar (regenerated)"))
        env.wordQueue.enqueue(inputWord: "hablar", mode: .regenerate(existingID: existing.id, existingCreatedAt: existing.createdAt), language: .english)

        let processor = WordQueueProcessor(sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertEqual(env.repository.allWords().count, 1)
        XCTAssertEqual(env.repository.allWords().first?.id, existing.id)
        XCTAssertEqual(env.repository.allWords().first?.content.word, "hablar (regenerated)")
    }

    func testNonRetryableFailureMarksFailedWithoutLooping() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        client.generateWordResult = .failure(.invalidAPIKey)
        let item = env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)

        let processor = WordQueueProcessor(sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertEqual(client.generateWordCallCount, 1, "a non-retryable error shouldn't be tried again")
        let reloaded = env.wordQueue.allItems().first { $0.id == item.id }
        XCTAssertEqual(reloaded?.status, .failed)
        XCTAssertNotNil(reloaded?.lastErrorMessage)
    }

    func testRetryableFailureThenSuccessEventuallySaves() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        client.generateWordScript = [.failure(.serverError(500)), .success(content(word: "hablar"))]
        env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)

        let processor = WordQueueProcessor(sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertEqual(client.generateWordCallCount, 2)
        XCTAssertTrue(env.wordQueue.allItems().isEmpty)
        XCTAssertEqual(env.repository.allWords().map(\.spanish), ["hablar"])
    }

    func testRetryableFailureExhaustingAttemptsMarksFailed() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        client.generateWordResult = .failure(.serverError(500))
        let item = env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)

        let processor = WordQueueProcessor(maxAttempts: 2, sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertEqual(client.generateWordCallCount, 2)
        let reloaded = env.wordQueue.allItems().first { $0.id == item.id }
        XCTAssertEqual(reloaded?.status, .failed)
    }

    /// Offline is checked before ever calling the AI, and the outer loop polls
    /// (via the injectable `sleep`) rather than spinning — this test's `sleep`
    /// cancels the processor the first time it's asked to wait, so the test
    /// can't hang even though, by design, draining while offline never finishes
    /// on its own.
    func testOfflineLeavesItemPendingAndNeverCallsTheAI() async {
        let (env, client) = makeEnvironment(connectivity: InstantConnectivity(isConnected: false))
        await selectModel(env, client)
        client.generateWordResult = .success(content(word: "hablar"))
        let item = env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)

        var processorRef: WordQueueProcessor!
        processorRef = WordQueueProcessor(sleep: { _ in await processorRef.cancel() })
        processorRef.drain(environment: env)
        await waitUntilDone(processorRef)

        XCTAssertEqual(client.generateWordCallCount, 0)
        let reloaded = env.wordQueue.allItems().first { $0.id == item.id }
        XCTAssertEqual(reloaded?.status, .pending)
    }

    func testDrainResetsItemOrphanedAsProcessingByAPreviousLaunch() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        let item = env.wordQueue.enqueue(inputWord: "hablar", mode: .new, language: .english)
        // Simulate the app having been killed mid-request last time: the
        // repository still shows `.processing` with nothing actually running.
        env.wordQueue.markProcessing(id: item.id)
        client.generateWordResult = .success(content(word: "hablar"))

        let processor = WordQueueProcessor(sleep: { _ in })
        processor.drain(environment: env)
        await waitUntilDone(processor)

        XCTAssertEqual(client.generateWordCallCount, 1, "an orphaned .processing item should be picked back up")
        XCTAssertTrue(env.wordQueue.allItems().isEmpty)
    }
}
