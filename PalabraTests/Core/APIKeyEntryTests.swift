import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class APIKeyEntryTests: XCTestCase {
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

    private func makeEnvironment(client: MockAIClient) -> AppEnvironment {
        AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "keyentry-\(UUID().uuidString)") ?? .standard)
        )
    }

    func testInvalidKeyIsNotSaved() async {
        let client = MockAIClient()
        client.listModelsResult = .failure(.invalidAPIKey)
        let env = makeEnvironment(client: client)

        let outcome = await APIKeyEntry.verifyAndSave("bad-key", environment: env)

        XCTAssertEqual(outcome, .invalid)
        XCTAssertFalse(env.hasAPIKey)
    }

    func testValidKeySavesAndPicksDefaultModel() async {
        let client = MockAIClient()
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        let env = makeEnvironment(client: client)

        let outcome = await APIKeyEntry.verifyAndSave("  good-key  ", environment: env)

        XCTAssertEqual(outcome, .saved)
        XCTAssertTrue(env.hasAPIKey)
        XCTAssertEqual(env.apiKey, "good-key")
        XCTAssertEqual(env.selectedModelID, "models/gemini-2.5-flash")
    }

    func testValidKeyAlsoPicksDefaultPronunciationModel() async {
        let client = MockAIClient()
        client.listModelsResult = .success([
            AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil),
            AIModel(id: "models/gemini-2.5-flash-tts", displayName: "Flash TTS", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
        ])
        let env = makeEnvironment(client: client)

        let outcome = await APIKeyEntry.verifyAndSave("good-key", environment: env)

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(env.selectedModelID, "models/gemini-2.5-flash")
        XCTAssertEqual(env.selectedTTSModelID, "models/gemini-2.5-flash-tts")
    }

    func testKeySavesCleanlyEvenWhenAccountHasNoTTSModels() async {
        let client = MockAIClient()
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        let env = makeEnvironment(client: client)

        let outcome = await APIKeyEntry.verifyAndSave("good-key", environment: env)

        // A missing pronunciation model must never turn a good key into a warning.
        XCTAssertEqual(outcome, .saved)
        XCTAssertNil(env.selectedTTSModelID)
    }

    func testOfflineDuringSaveStillSavesKeyWithWarning() async {
        let client = MockAIClient()
        client.listModelsResult = .failure(.offline)
        let env = makeEnvironment(client: client)

        let outcome = await APIKeyEntry.verifyAndSave("some-key", environment: env)

        XCTAssertEqual(outcome, .savedWithWarning(.offline))
        XCTAssertTrue(env.hasAPIKey)
    }

    func testDoesNotOverrideAnAlreadySelectedModel() async {
        let client = MockAIClient()
        client.listModelsResult = .success([
            AIModel(id: "models/gemini-2.5-pro", displayName: "Pro", description: nil, inputTokenLimit: nil, outputTokenLimit: nil),
            AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
        ])
        let env = makeEnvironment(client: client)
        env.selectedModelID = "models/gemini-2.5-pro"

        _ = await APIKeyEntry.verifyAndSave("some-key", environment: env)

        XCTAssertEqual(env.selectedModelID, "models/gemini-2.5-pro")
    }
}
