import XCTest
@testable import Palabra

/// Exam text that is chosen in code (so the source scan in `LocalizationTests` can't see it) has an Arabic entry.
final class ExamLocalizationTests: XCTestCase {
    private func arabicTable() throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle(for: Router.self).url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ar")
        )
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testEverySkillAndQuestionKindHasArabicText() throws {
        let table = try arabicTable()
        var keys: [String] = []
        for skill in ExamSkill.allCases { keys += [skill.title, skill.detail] }
        for kind in ExamQuestionKind.allCases { keys.append(kind.instruction) }
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testTheOtherExamMessagesHaveArabicText() throws {
        let table = try arabicTable()
        let keys = [
            "Exam", "Past Exams", "Start Exam", "Use AI", "Correct!", "Almost", "Not quite", "Mind the accents.", "Close: check the spelling.",
            "Some pairs took more than one try.", "Excellent!", "Well done", "Getting there", "Keep practising",
            "%lld of %lld", "%lld of %lld right", "%lld questions", "%lld words in this exam's pool", "%lld words added to Need Review.",
            "Last exam: %@", "Exams added: %lld.", "AI isn't set up, so this exam uses only your own words.",
            "AI couldn't be reached, so this exam uses only your own words.", "Turn on AI to use this.", "Not available on this device.",
            "Next", "See Results", "Wrong", "Right", "Example", "Your answer",
        ]
        for key in keys { XCTAssertFalse((table[key] ?? "").isEmpty, "missing Arabic string: \(key)") }
    }

    func testThePermissionPromptsHaveArabicText() throws {
        let url = try XCTUnwrap(Bundle(for: Router.self).url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "ar"))
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            XCTAssertFalse((table[key] ?? "").isEmpty, key)
        }
    }
}
