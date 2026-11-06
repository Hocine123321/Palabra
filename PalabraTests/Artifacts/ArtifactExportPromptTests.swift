import XCTest
@testable import Palabra

final class ArtifactExportPromptTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("storage.set", .local),
        makeCapability("ai.generate", .ai),
    ])

    private func export(_ request: String = "a verb trainer", language: SupportedLanguage = .english) -> String {
        ArtifactPrompts.exportPrompt(userPrompt: request, registry: registry, language: language)
    }

    func testExportAsksForOneHTMLDocumentAndNothingElse() {
        let text = export()
        XCTAssertTrue(text.contains("<!DOCTYPE html>"))
        XCTAssertTrue(text.contains("</html>"))
        XCTAssertTrue(text.contains("nothing else"))
        XCTAssertTrue(text.contains("no Markdown code fence"))
        XCTAssertTrue(text.contains("<title>"), "the page's name comes from its title")
    }

    func testExportHasNoEnvelope() {
        let text = export()
        XCTAssertFalse(text.contains("---PAYLOAD---"))
        XCTAssertFalse(text.contains("---END---"))
        XCTAssertFalse(text.contains("\"kind\""))
        XCTAssertFalse(text.contains("BLOCKS you may use"), "no JSON spec blocks: the answer is a page")
    }

    func testExportContainsTheRequestAndEveryCapability() {
        let text = export("a verb trainer")
        XCTAssertTrue(text.contains("REQUEST:\na verb trainer"))
        XCTAssertTrue(text.contains(registry.manual(including: [.read, .write, .ai, .local])))
        for name in ["library.words", "storage.set", "ai.generate"] {
            XCTAssertTrue(text.contains(name), "export misses \(name)")
        }
    }

    func testExportSharesTheSandboxRulesWithTheInAppPrompt() {
        let text = export()
        XCTAssertTrue(text.contains(ArtifactPrompts.sandboxRules))
        let inApp = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app])
        XCTAssertTrue(inApp.contains(ArtifactPrompts.sandboxRules), "one source of truth, so the two cannot drift")
        for rule in ["No external URLs", "localStorage", "palabra.call", "palabra.granted", "--accent", "palabra.dir"] {
            XCTAssertTrue(text.contains(rule), "export misses the rule about \(rule)")
        }
    }

    func testExportStatesTheExternalLimitNotTheInAppOne() {
        let text = export()
        XCTAssertTrue(text.contains("At most 2 MB"))
        XCTAssertFalse(text.contains("At most 20 KB"))
        XCTAssertFalse(text.contains("120 KB"))
    }

    func testExportWritesTheLanguageRequested() {
        XCTAssertTrue(export(language: .arabic).contains(SupportedLanguage.arabic.instructionName))
        XCTAssertTrue(export(language: .english).contains(SupportedLanguage.english.instructionName))
    }

    func testUpdateRequestCarriesTheChangeTitleAndWholePage() {
        let text = ArtifactPrompts.externalUpdateRequest(change: "add a score", currentTitle: "Trainer", currentHTML: "<html>old</html>")
        XCTAssertTrue(text.contains("add a score"))
        XCTAssertTrue(text.contains("TITLE: Trainer"))
        XCTAssertTrue(text.contains("CURRENT PAGE:\n<html>old</html>"))
        XCTAssertTrue(text.contains("complete new HTML document"))
    }

    func testInAppInstructionUsesTheSettingNotTheExportSize() {
        let text = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app], maxKB: 64)
        XCTAssertTrue(text.contains("At most 64 KB"))
        XCTAssertFalse(text.contains("2 MB"))
    }

    func testInAppInstructionStillUsesTheEnvelope() {
        let text = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app])
        XCTAssertTrue(text.contains("---PAYLOAD---"))
        XCTAssertTrue(text.contains("---END---"))
    }

    func testSpecOnlyGeminiInstructionHasNoAppRules() {
        let text = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec])
        XCTAssertFalse(text.contains("APP ARTIFACTS"))
    }

    /// What the exported prompt asks for must be exactly what the importer accepts.
    func testAnAnswerInTheRequestedShapeImportsCleanly() {
        let answer = "<!DOCTYPE html><html><head><title>Verb Trainer</title></head><body><script>palabra.call(\"library.words\", {})</script></body></html>"
        let generator = ArtifactGenerator(ai: MockAIClient(), registry: registry, allowedKinds: [.spec, .app])
        guard case .success(let draft) = generator.importDraft(answer, fixedTitle: nil, expectedKind: nil, userPrompt: "x") else { return XCTFail("a page in the requested shape must import") }
        XCTAssertEqual(draft.kind, .app)
        XCTAssertEqual(draft.title, "Verb Trainer")
        XCTAssertEqual(draft.requests, ["library.words"])
    }
}
