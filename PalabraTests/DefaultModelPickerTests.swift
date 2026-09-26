import XCTest
@testable import Palabra

final class DefaultModelPickerTests: XCTestCase {
    private func model(_ id: String) -> AIModel {
        AIModel(id: id, displayName: id, description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    }

    func testPrefersFlashOverOthers() {
        let models = [model("models/gemini-2.5-pro"), model("models/gemini-2.5-flash")]
        XCTAssertEqual(DefaultModelPicker.pick(from: models)?.id, "models/gemini-2.5-flash")
    }

    func testExcludesFlashLite() {
        let models = [model("models/gemini-2.5-pro"), model("models/gemini-2.5-flash-lite")]
        XCTAssertEqual(DefaultModelPicker.pick(from: models)?.id, "models/gemini-2.5-pro")
    }

    func testPreviewModelsAreDeprioritized() {
        let models = [model("models/gemini-2.5-flash-preview"), model("models/gemini-2.0-flash")]
        XCTAssertEqual(DefaultModelPicker.pick(from: models)?.id, "models/gemini-2.0-flash")
    }

    func testFallsBackToFirstModelWhenNothingMatches() {
        let models = [model("models/text-embedding-004")]
        XCTAssertEqual(DefaultModelPicker.pick(from: models)?.id, "models/text-embedding-004")
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(DefaultModelPicker.pick(from: []))
    }
}
