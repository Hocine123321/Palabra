import XCTest
@testable import Palabra

/// Exercises the real Google API. Skipped unless the `GEMINI_API_KEY`
/// repository secret is set (CI passes it through as `TEST_RUNNER_GEMINI_API_KEY`,
/// which xcodebuild delivers to this process as `GEMINI_API_KEY` — see
/// `.github/workflows/build-ipa.yml`). Never runs in this authoring
/// environment, which has no route to Google's API.
final class LiveSmokeTests: XCTestCase {
    private var apiKey: String? { ProcessInfo.processInfo.environment["GEMINI_API_KEY"] }

    func testListModelsAndGenerateWordAgainstRealAPI() async throws {
        guard let apiKey, !apiKey.isEmpty else {
            throw XCTSkip("GEMINI_API_KEY not set; skipping live API smoke test.")
        }
        let client = GeminiClient()

        guard case .success(let rawModels) = await client.listModels(apiKey: apiKey), !rawModels.isEmpty else {
            return XCTFail("expected a non-empty model list")
        }
        guard let model = DefaultModelPicker.pick(from: ModelFilter.apply(rawModels)) else {
            return XCTFail("no usable model in catalogue")
        }

        guard case .success(let content) = await client.generateWord("hablar", apiKey: apiKey, model: model) else {
            return XCTFail("expected a validated word for \"hablar\"")
        }
        XCTAssertFalse(content.word.isEmpty)
        XCTAssertEqual(content.examples.count, 3)
    }
}
