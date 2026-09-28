import XCTest
@testable import Palabra

final class TTSModelFilterTests: XCTestCase {
    private func model(_ id: String) -> AIModel {
        AIModel(id: id, displayName: id, description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    }

    func testKeepsOnlyTTSModels() {
        let models = [
            model("models/gemini-2.5-flash"),
            model("models/gemini-2.5-flash-tts"),
            model("models/imagen-3"),
            model("models/gemini-3.8-flash-lite-tts")
        ]
        let ids = Set(TTSModelFilter.apply(models).map(\.id))
        XCTAssertEqual(ids, ["models/gemini-2.5-flash-tts", "models/gemini-3.8-flash-lite-tts"])
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(TTSModelFilter.apply([model("models/Gemini-Flash-TTS")]).count, 1)
    }

    func testSortsNewerVersionNumbersFirst() {
        let old = model("models/gemini-2.5-flash-tts")
        let new = model("models/gemini-3.8-flash-tts")
        XCTAssertEqual(TTSModelFilter.apply([old, new]).map(\.id), ["models/gemini-3.8-flash-tts", "models/gemini-2.5-flash-tts"])
    }

    func testIsExactComplementOfTextModelFilterForTTSNames() {
        // A name the text filter drops for containing "tts" is one this filter keeps.
        let ttsModel = model("models/gemini-2.5-flash-tts")
        XCTAssertTrue(ModelFilter.apply([ttsModel]).isEmpty)
        XCTAssertEqual(TTSModelFilter.apply([ttsModel]).count, 1)
    }

    func testDefaultPickerPrefersStableNonLiteFlashTTS() {
        let filtered = TTSModelFilter.apply([
            model("models/gemini-3.8-flash-tts"),
            model("models/gemini-3.8-flash-lite-tts"),
            model("models/gemini-3.1-flash-tts-preview"),
            model("models/gemini-2.5-pro-preview-tts")
        ])
        XCTAssertEqual(DefaultModelPicker.pick(from: filtered)?.id, "models/gemini-3.8-flash-tts")
    }
}
