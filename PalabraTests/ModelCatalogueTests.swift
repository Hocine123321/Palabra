import XCTest
@testable import Palabra

@MainActor
final class ModelCatalogueTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func model(_ id: String) -> AIModel {
        AIModel(id: id, displayName: id, description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    }

    func testRefreshSuccessFiltersAndCaches() async {
        let catalogue = ModelCatalogue(cacheDirectory: tempDir)
        let client = MockAIClient()
        client.listModelsResult = .success([model("models/gemini-2.5-flash"), model("models/tts-1")])

        await catalogue.refresh(apiKey: "key", using: client)

        XCTAssertEqual(catalogue.models.map(\.id), ["models/gemini-2.5-flash"])
        guard case .loaded = catalogue.status else { return XCTFail("expected .loaded, got \(catalogue.status)") }
    }

    func testCacheIsUsedOnRelaunchWithoutNetwork() async {
        let catalogue = ModelCatalogue(cacheDirectory: tempDir)
        let client = MockAIClient()
        client.listModelsResult = .success([model("models/gemini-2.5-flash")])
        await catalogue.refresh(apiKey: "key", using: client)

        let relaunched = ModelCatalogue(cacheDirectory: tempDir)
        relaunched.loadCacheIfPresent()

        XCTAssertEqual(relaunched.models.map(\.id), ["models/gemini-2.5-flash"])
        guard case .loaded = relaunched.status else { return XCTFail("expected .loaded, got \(relaunched.status)") }
    }

    func testFailedRefreshKeepsPreviousCache() async {
        let catalogue = ModelCatalogue(cacheDirectory: tempDir)
        let client = MockAIClient()
        client.listModelsResult = .success([model("models/gemini-2.5-flash")])
        await catalogue.refresh(apiKey: "key", using: client)

        client.listModelsResult = .failure(.rateLimited)
        await catalogue.refresh(apiKey: "key", using: client)

        XCTAssertEqual(catalogue.models.map(\.id), ["models/gemini-2.5-flash"])
        guard case .failed(.rateLimited, let hasCache) = catalogue.status else { return XCTFail("expected .failed, got \(catalogue.status)") }
        XCTAssertTrue(hasCache)
    }

    func testEmptyResultAfterFilteringKeepsPreviousCache() async {
        let catalogue = ModelCatalogue(cacheDirectory: tempDir)
        let client = MockAIClient()
        client.listModelsResult = .success([model("models/gemini-2.5-flash")])
        await catalogue.refresh(apiKey: "key", using: client)

        client.listModelsResult = .success([model("models/tts-1")])
        await catalogue.refresh(apiKey: "key", using: client)

        XCTAssertEqual(catalogue.models.map(\.id), ["models/gemini-2.5-flash"])
        guard case .failed(.emptyCatalogue, let hasCache) = catalogue.status else { return XCTFail("expected .failed(.emptyCatalogue), got \(catalogue.status)") }
        XCTAssertTrue(hasCache)
    }

    func testFirstFailureWithNoCacheReportsHasCacheFalse() async {
        let catalogue = ModelCatalogue(cacheDirectory: tempDir)
        let client = MockAIClient()
        client.listModelsResult = .failure(.offline)

        await catalogue.refresh(apiKey: "key", using: client)

        guard case .failed(.offline, let hasCache) = catalogue.status else { return XCTFail("expected .failed(.offline), got \(catalogue.status)") }
        XCTAssertFalse(hasCache)
    }
}
