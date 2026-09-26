import XCTest
@testable import Palabra

final class ModelFilterTests: XCTestCase {
    private func model(_ id: String) -> AIModel {
        AIModel(id: id, displayName: id, description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    }

    func testDropsTTSImageAudioModels() {
        let models = [model("models/gemini-2.5-flash"), model("models/text-to-speech-tts"), model("models/imagen-3"), model("models/gemini-audio-live")]
        XCTAssertEqual(ModelFilter.apply(models).map(\.id), ["models/gemini-2.5-flash"])
    }

    func testSortsNewerVersionNumbersFirst() {
        let old = model("models/gemini-1.5-flash")
        let new = model("models/gemini-2.5-flash")
        XCTAssertEqual(ModelFilter.apply([old, new]).map(\.id), ["models/gemini-2.5-flash", "models/gemini-1.5-flash"])
    }
}
