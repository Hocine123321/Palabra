import XCTest
@testable import Palabra

final class LocalizationTests: XCTestCase {
    private func arabicTable() throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle(for: Router.self).url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ar")
        )
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    // Localization is keyed by the English string; a missing key shows English inside an RTL layout.
    func testArabicStringsHaveSpanishHubKey() throws {
        XCTAssertFalse((try arabicTable()["Spanish"] ?? "").isEmpty)
    }

    func testArabicStringsHaveArtifactKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Artifacts", "New Artifact", "No artifacts yet", "Ask the AI for a table, chart, roadmap or checklist.",
            "Describe what you want", "Describe the change", "Generate", "Generating…", "Save", "Refine", "Discard",
            "Update", "Versions", "Version %lld", "Restore", "Current", "Delete", "Dismiss", "Ask for a change",
            "Delete this artifact?", "Couldn't load data", "No data yet", "Not supported in this version yet",
            "Update Palabra to open this artifact.", "Try updating this artifact.",
            "This artifact wants to", "Allow", "Not now", "Read your data", "Change your data", "Use your AI quota",
            "Save its own data", "Errors", "Fix with AI",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    /// Every message the artifact flow can show must be translated (they are looked up by English text).
    func testArabicStringsCoverArtifactErrorMessages() throws {
        let table = try arabicTable()
        let errors: [ArtifactGenError] = [.truncated, .malformedEnvelope(""), .invalidSpec(""), .invalidApp(""), .kindNotAvailable, .tooLargeToExtend]
        for error in errors { XCTAssertFalse((table[error.userMessage] ?? "").isEmpty, "missing Arabic string: \(error.userMessage)") }
        let storage = [
            "This artifact is too large to save. Ask for a simpler version.",
            "This artifact's storage is full.",
            "The artifact could not be saved.",
        ]
        for key in storage { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }
}
