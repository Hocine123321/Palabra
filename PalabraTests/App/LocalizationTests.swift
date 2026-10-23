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

    func testArabicStringsHaveChatKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Chat", "New chat", "No chats yet", "Message…", "Apply", "Waiting for your OK", "Done", "Not applied", "Working…",
            "Ask me anything, or have me change your library, decks and review list.",
            "Add some words to my library", "What should I review?", "Make a flashcard deck for me", "Teach me a new word",
            "Explain it more simply", "Give me another example", "Is it formal or informal?", "Make flashcards for it",
            "Looked through your library", "Opened a word", "Checked your progress", "Checked your review list", "Checked your decks", "Looked something up",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveAssistantSettingsKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Assistant", "Chat Assistant", "Replies", "Reply Length", "Concise", "Detailed",
            "For example: always add an example sentence", "Optional. The assistant follows these in every chat.",
            "Changes", "Ask Before Making Changes", "Every change the assistant proposes waits for your Apply.",
            "Changes are applied as soon as the assistant proposes them. You can't undo them from the chat.",
            "What the Assistant Can Use", "Switch a part off and the assistant can no longer read or change it.",
            "Library and Progress", "Adding and Organizing Words", "Flashcards", "Review List",
            "Delete All Chats", "Delete all chats? This can't be undone.",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveNewArtifactPageKeys() throws {
        let table = try arabicTable()
        var keys = [
            "What do you want to make?", "Describe it, or start from an idea.", "Everything you don't mention stays as it is.",
            "A table, a chart, a plan, a little game…", "For example: add a column for examples", "Format", "Auto", "Page", "Interactive app",
            "The AI picks what fits your request.", "Tables, charts, roadmaps and checklists. Safe: it can only read your data.",
            "Buttons, games and trackers. It asks your permission before using your data.", "Ideas", "Quick changes",
        ]
        keys += ArtifactIdea.all.flatMap { [$0.title, $0.subtitle] }
        keys += ArtifactQuickChange.all
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveStudyRefinementKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Decks", "Today", "Nothing due today", "%lld-day streak", "Review a card to start a streak", "Reviews in the last 7 days: %lld",
            "Make a deck from notes", "Reviewed", "Correct", "Day streak", "New Card", "This card is already in the deck.",
            "Add Card", "Due", "New", "%lld new",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveNeedReviewKeys() throws {
        let table = try arabicTable()
        let keys = ["Need Review", "Needs review", "Mark as learned", "Nothing to review", "Words your artifacts flag will show up here."]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    /// The camera prompt is where the photo privacy wording matters most, so Arabic users get it in Arabic.
    func testCameraPermissionTextIsTranslated() throws {
        let url = try XCTUnwrap(
            Bundle(for: Router.self).url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "ar")
        )
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertFalse((table["NSCameraUsageDescription"] ?? "").isEmpty)
    }

    func testArabicStringsHaveSolveKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Solve", "Problem", "Answer", "Answer not found", "It may have been deleted.", "Recent", "Did you mean",
            "Take Photo", "Choose Photo", "Reading your photo…", "Solving…", "Check the text a photo gave you before you solve it.",
            "Type or scan a problem, for example x^2 - 4 = 0", "Wolfram|Alpha App ID",
            "Replace App ID", "Remove App ID", "Save App ID", "Get a free App ID", "Remove your App ID?",
            "About %lld of %lld free solves used this month", "Answers are saved, so opening one again costs nothing.",
            "Powered by Wolfram|Alpha", "Show steps", "Loading steps…", "Uses one more free call.", "Open in Wolfram|Alpha",
            "Copy", "Copied", "Share",
            "Written by Gemini from the checked answer.", "Solved on your device.",
            "Solved by Gemini. Double-check it before you rely on it.",
            "Solves on your device first. Gemini writes the steps and handles harder problems.",
            "Photos are read by Gemini when a key is set, otherwise on your device.",
            "Listen", "Stop", "Sort", "Newest first", "Oldest first", "A to Z",
            "Edit Problem", "Cancel", "Clear", "Share",
            "More", "Add word", "Collapsed", "Expanded",
            "Result", "Input", "Decimal approximation", "Factored form", "Expanded form", "Simplified form", "Steps",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    /// Every message the Solve tab can show is looked up by its English text.
    func testArabicStringsCoverSolveMessages() throws {
        let table = try arabicTable()
        let solveErrors: [SolveError] = [.emptyInput, .missingKey, .invalidKey, .rateLimited, .noResult(suggestions: []), .noSteps, .network, .malformed, .unreadablePhoto, .unsolvedPhoto(problem: "")]
        for error in solveErrors { XCTAssertFalse((table[error.userMessage] ?? "").isEmpty, "missing Arabic string: \(error.userMessage)") }
        for error in [RecognitionError.unreadable, .nothingFound] {
            XCTAssertFalse((table[error.userMessage] ?? "").isEmpty, "missing Arabic string: \(error.userMessage)")
        }
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
    func testArabicStringsHaveModelHealthKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Working", "Busy right now", "Quota used up", "Unstable", "Not available", "Testing…", "Test This Model", "Test",
            "Stop Testing", "Test All Models", "Only Working Models", "Working models only", "Switch Models Automatically", "Backup Model", "Automatic",
            "Choose a Backup Model", "Switched to a backup model", "Using %@ for now because your usual model is busy.",
            "Marks come from your recent requests and tests. A model with no mark hasn't been used lately.",
            "When your model is busy, out of quota or removed, the app answers with another one that works and tells you. Automatic picks from the models marked Working first.",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveSolveSettingsKeys() throws {
        let table = try arabicTable()
        var keys = [
            "Solve Settings", "Photos", "Solve on this device first", "Gemini Model", "Solving", "Wolfram|Alpha (optional)",
            "Choose a Solve Model", "Same as your main model", "Solving your photo…",
            "Add your API key in Settings so Gemini can read and solve photos.",
            "Photos go to Gemini, which reads and solves them in one step.", "Photos are read on your device and never leave it.",
            "Gemini couldn't be reached, so the text was read on this device. Check it, then tap Solve.",
            "No Gemini key or model is set, so the text was read on this device. Check it, then tap Solve.",
            "Optional. A Wolfram|Alpha App ID adds Wolfram's answers for typed problems your device can't solve.",
            "The on-device engine is instant and works offline for standard algebra and calculus. Turn it off to send every typed problem to Gemini. The model is used for photos, harder problems and steps.",
        ]
        // Strings built from the photo modes are looked up by their English text too.
        keys += [
            "Send photo to Gemini", "Read text, then solve", "Read text on this device",
            "Gemini looks at the photo itself, copies the whole problem and solves it in one step. Best for handwriting, several parts and diagrams. Needs your API key.",
            "Gemini copies the problem as text first (this device does it if Gemini can't). You check the text, then tap Solve.",
            "The photo never leaves this device. Reading is weaker on handwriting and maths notation, so check the text before you solve.",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testArabicStringsHaveReliabilityKeys() throws {
        let table = try arabicTable()
        let keys = [
            "Reliability", "Backup API Key", "Backup key", "Main key", "Using now", "Retry Automatically", "Retrying",
            "Remove the backup key?", "Remove Backup Key", "Paste a key from another account", "Verify and Save",
            "Recent Problems", "No problems so far.", "Scope", "Backup key on", "No backup key",
            "Automatic Tries: %lld", "First Wait: %lld s", "Longest Automatic Wait: %lld s",
            "Waiting for a connection…", "(backup key)", "Retrying in %llds (%lld of %lld)", "Retrying now… (%lld of %lld)",
            "Try Again", "Retry with Longer Waits", "I tried 1 time already.", "I tried %lld times already.",
            "The model \"%@\" no longer exists. Choose another one in Settings.", "Generating \"%@\"",
            "That's the same as your main key. Use a key from a different account.", "Couldn't save that key.",
            "Your model was removed, so I switched to %@.", "Added \"%@\" now that you're back online.",
            "Switched to your backup key", "Your main key failed, so the backup key is being used.",
            "Automatic retries and a backup API key for when your main one fails.",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    /// Every wording the retry overlay and the log can show is looked up by its English text.
    @MainActor
    func testArabicStringsCoverResilienceWording() throws {
        let table = try arabicTable()
        let errors: [AIError] = [
            .missingAPIKey, .noModelSelected, .modelUnavailable("m"), .offline, .timeout, .invalidAPIKey, .permissionDenied,
            .rateLimited, .quotaExhausted, .serverError(500), .blocked(nil), .truncated, .malformedResponse,
            .validationFailed([]), .emptyCatalogue, .cancelled, .unknown(nil, ""),
        ]
        var keys: [String] = []
        for error in errors {
            keys += [error.shortReason, error.headline, error.settingsButtonTitle]
            keys += [error.advice(hasBackupKey: true), error.advice(hasBackupKey: false)]
        }
        for reason in [KeyHealth.Reason.rateLimited, .quotaExhausted, .rejected, .flaky] {
            keys.append(ReliabilitySettingsView.benchText(reason))
        }
        keys += [
            "Loading models", "Chat reply", "Pronunciation", "AI request", "Organizing words",
            "Stopped", "Not retryable", "Stopped while offline", "Switched to backup key", "Stopped by you",
        ]
        for key in Set(keys) { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    /// Guards the whole app: any fixed text passed to Text, Button, Label and similar must have an
    /// Arabic entry, or it shows English inside the RTL layout. Reads the sources next to this file,
    /// and is skipped where they are not on disk.
    func testEveryFixedUIStringHasArabic() throws {
        let table = try arabicTable()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Palabra")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Features").path) else {
            throw XCTSkip("App sources are not available to the test runner")
        }
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|Button|Label|Toggle|Section|NavigationLink|Picker|Stepper|TextField|SecureField|navigationTitle|confirmationDialog|Chip)\(\s*(?:text:\s*)?"((?:[^"\\]|\\.)+)""#
        )
        let brandNames: Set<String> = ["Palabra"]
        var missing: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent("Features"), includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let r = Range(match.range(at: 1), in: source) else { continue }
                var text = String(source[r])
                if text.contains("\\(") { continue } // interpolated: its format key is checked by hand
                text = text.replacingOccurrences(of: "\\u{2026}", with: "…").replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\'", with: "'")
                guard text.contains(where: \.isLetter), !brandNames.contains(text) else { continue }
                if (table[text] ?? "").isEmpty { missing.append("\(text)  [\(file.lastPathComponent)]") }
            }
        }
        XCTAssertTrue(missing.isEmpty, "UI strings without an Arabic entry:\n" + missing.sorted().joined(separator: "\n"))
    }
}
