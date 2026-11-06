import XCTest
@testable import Palabra

final class ArtifactExportPromptTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("storage.set", .local),
        makeCapability("ai.generate", .ai),
    ])

    private func export(_ request: String = "a verb trainer") -> String {
        ArtifactPrompts.exportPrompt(userPrompt: request, registry: registry, language: .english)
    }

    func testExportContainsSystemRulesManualAndRequest() {
        let text = export("a verb trainer")
        let rules = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app], maxKB: 120)
        XCTAssertTrue(text.contains(rules))
        XCTAssertTrue(text.contains(registry.manual(including: [.read, .write, .ai, .local])))
        XCTAssertTrue(text.contains("a verb trainer"))
        XCTAssertTrue(text.contains("---PAYLOAD---"))
        XCTAssertTrue(text.contains("---END---"))
        for name in ["library.words", "storage.set", "ai.generate"] {
            XCTAssertTrue(text.contains(name), "export misses \(name)")
        }
    }

    func testExportSaysAtMost120KB() {
        XCTAssertTrue(export().contains("At most 120 KB"))
        XCTAssertFalse(export().contains("At most 20 KB"))
    }

    func testInAppInstructionUsesTheSettingNotTheExportSize() {
        let text = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app], maxKB: 64)
        XCTAssertTrue(text.contains("At most 64 KB"))
        XCTAssertFalse(text.contains("120 KB"))
    }

    func testExportEndsWithEnvelopeOnlyInstruction() {
        let last = export().components(separatedBy: "\n\n").last ?? ""
        XCTAssertTrue(last.contains("no code fences"))
        XCTAssertTrue(last.contains("no commentary"))
    }

    func testSpecOnlyGeminiInstructionHasNoAppRules() {
        let text = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec])
        XCTAssertFalse(text.contains("APP ARTIFACTS"))
    }
}
