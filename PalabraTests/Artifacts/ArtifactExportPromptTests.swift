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

    /// The person is in a full AI app, which delivers an interactive page as an artifact or a file. Nothing in the prompt may force
    /// it to paste the HTML as plain text: that limit belongs to the API route, not to this one.
    func testExportDoesNotForceTheAnswerAsText() {
        let text = export().lowercased()
        for forbidden in ["nothing else", "no markdown", "code fence", "as plain text", "starts with <!doctype", "ends with </html>", "no explanation", "reply with the complete html"] {
            XCTAssertFalse(text.contains(forbidden), "the prompt must not say: \(forbidden)")
        }
    }

    func testExportLetsTheAIDeliverItTheNormalWay() {
        let text = export()
        XCTAssertTrue(text.contains("the way you normally make an interactive page"))
        XCTAssertTrue(text.contains("an artifact, a file"))
        XCTAssertTrue(text.contains("<title>"), "the page's name comes from its title")
        XCTAssertTrue(text.contains("ONE self-contained HTML page"))
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

    func testExportStatesThePersonsExternalLimitNotTheInAppOne() {
        XCTAssertTrue(export().contains("At most 2 MB"), "the default external cap")
        let small = ArtifactPrompts.exportPrompt(userPrompt: "x", registry: registry, language: .english, maxKB: 512)
        XCTAssertTrue(small.contains("At most 512 KB"))
        XCTAssertFalse(small.contains("At most 2 MB"))
        XCTAssertFalse(export().contains("At most 20 KB"))
    }

    func testDescribeLimit() {
        XCTAssertEqual(ArtifactPrompts.describeLimit(kb: 2048), "2 MB")
        XCTAssertEqual(ArtifactPrompts.describeLimit(kb: 1024), "1 MB")
        XCTAssertEqual(ArtifactPrompts.describeLimit(kb: 640), "640 KB")
        XCTAssertEqual(ArtifactPrompts.describeLimit(kb: 99_999), "2 MB", "clamped to the range")
        XCTAssertEqual(ArtifactPrompts.describeLimit(kb: 1), "128 KB")
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
        XCTAssertTrue(text.contains("complete new page"))
        XCTAssertFalse(text.lowercased().contains("code fence"))
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
