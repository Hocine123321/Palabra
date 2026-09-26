import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class AppEnvironmentTests: XCTestCase {
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

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            ai: StubAIClient(),
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "aenv-\(UUID().uuidString)") ?? .standard)
        )
    }

    func testSaveAndRemoveAPIKeyTogglesHasAPIKey() {
        let env = makeEnvironment()
        XCTAssertFalse(env.hasAPIKey)
        XCTAssertTrue(env.saveAPIKey("AIzaSyExampleKey1234"))
        XCTAssertTrue(env.hasAPIKey)
        env.removeAPIKey()
        XCTAssertFalse(env.hasAPIKey)
    }

    func testSelectedModelResolvesFromCatalogueByID() async {
        let env = makeEnvironment()
        let client = MockAIClient()
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
        XCTAssertEqual(env.selectedModel?.id, "models/gemini-2.5-flash")
    }

    func testSelectedModelIsNilWhenSelectionMissingFromCatalogue() {
        let env = makeEnvironment()
        env.selectedModelID = "models/does-not-exist"
        XCTAssertNil(env.selectedModel)
    }
}
