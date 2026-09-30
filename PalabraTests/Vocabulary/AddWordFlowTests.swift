import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class AddWordFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        keychain = KeychainStore()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    private func makeEnvironment(hasKey: Bool, selectedModelID: String? = nil) -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "awf-\(UUID().uuidString)") ?? .standard)
        )
        if hasKey { env.saveAPIKey("test-api-key") } else { env.removeAPIKey() }
        env.selectedModelID = selectedModelID
        return (env, client)
    }

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

    private func selectFlashModel(_ env: AppEnvironment, _ client: MockAIClient) async {
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
    }

    func testMissingAPIKeyFailsImmediately() async {
        let (env, _) = makeEnvironment(hasKey: false)
        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        XCTAssertEqual(flow.phase, .failed(.missingAPIKey))
    }

    func testNoModelSelectedFails() async {
        let (env, _) = makeEnvironment(hasKey: true, selectedModelID: nil)
        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        XCTAssertEqual(flow.phase, .failed(.noModelSelected))
    }

    func testSelectedModelMissingFromCatalogueFails() async {
        let (env, _) = makeEnvironment(hasKey: true, selectedModelID: "models/gone")
        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        XCTAssertEqual(flow.phase, .failed(.modelUnavailable("models/gone")))
    }

    func testSuccessDetectsReinterpretedWord() async {
        let (env, client) = makeEnvironment(hasKey: true)
        await selectFlashModel(env, client)
        client.generateWordResult = .success(content(word: "hablar"))

        let flow = AddWordFlow(inputWord: "ablar", mode: .new, environment: env)
        await flow.start()

        guard case .loaded(let loaded) = flow.phase else { return XCTFail("expected loaded, got \(flow.phase)") }
        XCTAssertEqual(loaded.word, "hablar")
        XCTAssertTrue(flow.interpretedDifferently)
    }

    func testSuccessSameWordDoesNotFlagReinterpretation() async {
        let (env, client) = makeEnvironment(hasKey: true)
        await selectFlashModel(env, client)
        client.generateWordResult = .success(content(word: "hablar"))

        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        XCTAssertFalse(flow.interpretedDifferently)
    }

    func testRetryAfterFailureCanSucceed() async {
        let (env, client) = makeEnvironment(hasKey: true)
        await selectFlashModel(env, client)
        client.generateWordResult = .failure(.rateLimited)

        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        XCTAssertEqual(flow.phase, .failed(.rateLimited))

        client.generateWordResult = .success(content(word: "hablar"))
        await flow.retry()
        guard case .loaded = flow.phase else { return XCTFail("expected loaded after retry") }
    }

    func testSaveNewInsertsWord() async {
        let (env, client) = makeEnvironment(hasKey: true)
        await selectFlashModel(env, client)
        client.generateWordResult = .success(content(word: "hablar"))

        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        await flow.start()
        let saved = flow.save()

        XCTAssertNotNil(saved)
        XCTAssertEqual(env.repository.allWords().count, 1)
    }

    func testSaveRegeneratePreservesExistingIDAndCreatedAt() async {
        let (env, client) = makeEnvironment(hasKey: true)
        await selectFlashModel(env, client)

        let existing = env.repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(word: "hablar"), rawJSON: Data())
        let originalCreatedAt = existing.createdAt

        client.generateWordResult = .success(content(word: "hablar (regenerated)"))
        let flow = AddWordFlow(inputWord: "hablar", mode: .regenerate(existingID: existing.id, existingCreatedAt: existing.createdAt), environment: env)
        await flow.start()
        let saved = flow.save()

        XCTAssertEqual(saved?.id, existing.id)
        XCTAssertEqual(saved?.createdAt, originalCreatedAt)
        XCTAssertEqual(saved?.content.word, "hablar (regenerated)")
        XCTAssertEqual(env.repository.allWords().count, 1)
    }

    func testSaveWhileLoadingReturnsNil() {
        let (env, _) = makeEnvironment(hasKey: true)
        let flow = AddWordFlow(inputWord: "hablar", mode: .new, environment: env)
        XCTAssertNil(flow.save())
    }
}
