import Foundation
import Vision

enum RecognitionError: Error, Equatable {
    case unreadable
    case nothingFound
    /// The preferred reader (Gemini) could not be used: no key, offline, rate limited. Callers fall back.
    case unavailable

    /// A localization key.
    var userMessage: String {
        switch self {
        case .unreadable: return "Couldn't read that photo. Try another one."
        case .nothingFound: return "No text found in the photo. Get closer or add light."
        case .unavailable: return "Couldn't read that photo. Try another one."
        }
    }
}

/// Reads the text of a photo. The live chain is Gemini (the person's key) with on-device Apple Vision as the fallback.
protocol TextRecognizer: Sendable {
    func recognize(imageData: Data) async -> Result<String, RecognitionError>
}

/// On-device (Apple Vision): free and offline, but weak on maths notation and handwriting.
struct VisionTextRecognizer: TextRecognizer {
    /// Maths (the default): English, no language correction, because "correction" turns symbols and variables into words.
    /// Prose, such as a page of a book: pass the languages and turn the correction on.
    var languages: [String] = ["en-US"]
    var usesLanguageCorrection = false

    func recognize(imageData: Data) async -> Result<String, RecognitionError> {
        let languages = languages, correction = usesLanguageCorrection
        return await Task.detached(priority: .userInitiated) { Self.run(imageData, languages: languages, usesLanguageCorrection: correction) }.value
    }

    /// Spanish words first, then English for the translations printed beside them.
    static let prose = VisionTextRecognizer(languages: ["es-ES", "en-US"], usesLanguageCorrection: true)

    static func run(_ data: Data, languages: [String] = ["en-US"], usesLanguageCorrection: Bool = false) -> Result<String, RecognitionError> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.automaticallyDetectsLanguage = false
        // A language this iOS cannot read is dropped (asking for it would fail the whole request).
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let usable = languages.filter { supported.isEmpty || supported.contains($0) }
        request.recognitionLanguages = usable.isEmpty ? ["en-US"] : usable
        do {
            try VNImageRequestHandler(data: data, options: [:]).perform([request])
        } catch {
            return .failure(.unreadable)
        }
        // Vision's origin is the bottom-left corner: higher midY is higher on the page.
        let lines = (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.isEmpty ? .failure(.nothingFound) : .success(lines.joined(separator: "\n"))
    }
}

/// UI tests: pretends every photo says "3 × 4 + x²".
struct StubTextRecognizer: TextRecognizer {
    func recognize(imageData: Data) async -> Result<String, RecognitionError> {
        .success("3 \u{00D7} 4 + x\u{00B2}")
    }
}
