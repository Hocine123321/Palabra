import XCTest
@testable import Palabra

final class ArtifactPromptSettingsTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("storage.set", .local),
        makeCapability("ai.generate", .ai),
    ])

    private func export(_ config: ArtifactPromptSettings, request: String = "a verb trainer") -> String {
        ArtifactPrompts.exportPrompt(userPrompt: request, registry: registry, language: .english, maxKB: 512, config: config)
    }

    private func inApp(_ config: ArtifactPromptSettings, kinds: Set<ArtifactKind> = [.spec, .app]) -> String {
        ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: kinds, maxKB: 40, config: config)
    }

    // MARK: the built-in prompt is unchanged

    func testDefaultExportKeepsItsShape() {
        let text = export(.default)
        let rules = text.range(of: "\n\nRULES\n- At most 512 KB, and only as large as the request needs")
        let caps = text.range(of: "\n\nCAPABILITIES the page may call with palabra.call")
        let request = text.range(of: "\n\nREQUEST:\na verb trainer")
        XCTAssertNotNil(rules)
        XCTAssertNotNil(caps)
        XCTAssertNotNil(request)
        XCTAssertLessThan(rules!.lowerBound, caps!.lowerBound)
        XCTAssertLessThan(caps!.lowerBound, request!.lowerBound)
        XCTAssertTrue(text.hasPrefix("Build an interactive page for Palabra"))
        XCTAssertTrue(text.contains(ArtifactPrompts.sandboxRules + "\n- Write all visible text in English."))
        XCTAssertTrue(text.hasSuffix("REQUEST:\na verb trainer"))
    }

    func testDefaultInAppInstructionKeepsItsShape() {
        let text = inApp(.default)
        XCTAssertTrue(text.hasPrefix("You build \"artifacts\" for Palabra"))
        XCTAssertTrue(text.contains("OUTPUT FORMAT (follow exactly"))
        XCTAssertTrue(text.contains("BLOCKS you may use"))
        XCTAssertTrue(text.contains("LIVE DATA:"))
        XCTAssertTrue(text.contains("\nRULES\n- Keep it compact"))
        XCTAssertTrue(text.contains(ArtifactPrompts.sandboxRules))
    }

    // MARK: the prompt for another AI

    func testARuleCanBeSwitchedOff() {
        var config = ArtifactPromptSettings()
        config.setRule(ArtifactPrompts.Rule.language.rawValue, enabled: false, text: nil)
        let text = export(config)
        XCTAssertFalse(text.contains("Write all visible text in"))
        XCTAssertTrue(text.contains("At most 512 KB"), "the other rules stay")
    }

    func testARuleCanBeReworded() {
        var config = ArtifactPromptSettings()
        config.setRule(ArtifactPrompts.Rule.size.rawValue, enabled: true, text: "Stay under {{MAX_SIZE}} please")
        let text = export(config)
        XCTAssertTrue(text.contains("- Stay under 512 KB please"), "a missing bullet is added and the size is filled in")
        XCTAssertFalse(text.contains("only as large as the request needs"))
    }

    func testExtraRulesComeAfterTheBuiltInOnesAsBullets() {
        var config = ArtifactPromptSettings()
        config.extraRules = "Use large buttons\n\n- Prefer a dark palette\n"
        let text = export(config)
        let own = text.range(of: "- Use large buttons\n- Prefer a dark palette")
        let builtIn = text.range(of: "- Never invent the user's own data")
        XCTAssertNotNil(own)
        XCTAssertNotNil(builtIn)
        XCTAssertLessThan(builtIn!.lowerBound, own!.lowerBound)
    }

    func testIntroAndCapabilityListAreOptional() {
        var config = ArtifactPromptSettings()
        config.intro = "Make a small page."
        config.includeCapabilities = false
        let text = export(config)
        XCTAssertTrue(text.hasPrefix("Make a small page.\n\nRULES"))
        XCTAssertFalse(text.contains("CAPABILITIES the page may call"))
        XCTAssertFalse(text.contains("library.words"))
        XCTAssertTrue(text.hasSuffix("REQUEST:\na verb trainer"))
    }

    func testAWholeTemplateReplacesEverythingAndFillsPlaceholders() {
        var config = ArtifactPromptSettings()
        config.template = "Task: {{REQUEST}}\nLimit {{MAX_SIZE}} in {{LANGUAGE}}\n{{RULES}}"
        let text = export(config, request: "a timer")
        XCTAssertTrue(text.hasPrefix("Task: a timer\nLimit 512 KB in English\n- At most 512 KB"))
        XCTAssertFalse(text.contains("Build an interactive page for Palabra"))
        XCTAssertFalse(text.contains("{{"))
    }

    func testATemplateWithoutTheRequestStillCarriesIt() {
        var config = ArtifactPromptSettings()
        config.template = "Be brief."
        XCTAssertEqual(export(config, request: "a timer"), "Be brief.\n\nREQUEST:\na timer")
    }

    func testABlankTemplateIsIgnored() {
        var config = ArtifactPromptSettings()
        config.template = "   \n "
        XCTAssertEqual(export(config), export(.default))
    }

    func testTheBuiltInTemplateRebuildsTheBuiltInPrompt() {
        var config = ArtifactPromptSettings()
        config.template = ArtifactPrompts.externalTemplateText
        XCTAssertEqual(export(config), export(.default), "editing starts from text that behaves exactly like the built-in prompt")
    }

    // MARK: the in-app instruction

    func testInAppExtraRulesAreAppended() {
        var config = ArtifactPromptSettings()
        config.inAppExtraRules = "Keep tables under ten rows"
        let text = inApp(config)
        XCTAssertTrue(text.hasSuffix("- Keep tables under ten rows"))
        XCTAssertTrue(text.contains("\"requests\" lists exactly"))
    }

    func testInAppTemplateWithoutTheOutputFormatGetsItBack() {
        var config = ArtifactPromptSettings()
        config.inAppTemplate = "Just make something nice."
        let text = inApp(config)
        XCTAssertTrue(text.hasPrefix("Just make something nice."))
        XCTAssertTrue(text.contains("OUTPUT FORMAT (follow exactly"), "the app reads the answer by this format")
        XCTAssertTrue(text.contains(ArtifactPrompts.endMarker))
        XCTAssertTrue(text.contains("APP ARTIFACTS"), "app rules come back when apps are allowed")
        XCTAssertFalse(inApp(config, kinds: [.spec]).contains("APP ARTIFACTS"))
    }

    func testInAppTemplatePlaceholdersAreFilled() {
        var config = ArtifactPromptSettings()
        config.inAppTemplate = "{{OUTPUT_FORMAT}}\nIn {{LANGUAGE}}, up to {{MAX_SIZE}}.\n{{RULES}}"
        let text = inApp(config)
        XCTAssertTrue(text.contains("In English, up to 40 KB."))
        XCTAssertFalse(text.contains("{{"))
        XCTAssertEqual(text.components(separatedBy: "OUTPUT FORMAT (follow exactly").count - 1, 1, "not added twice")
    }

    func testTheBuiltInInAppTemplateBehavesLikeTheBuiltInInstruction() {
        var config = ArtifactPromptSettings()
        config.inAppTemplate = ArtifactPrompts.inAppTemplateText
        XCTAssertEqual(inApp(config), inApp(.default))
        XCTAssertEqual(inApp(config, kinds: [.spec]), inApp(.default, kinds: [.spec]))
    }

    // MARK: storage

    func testSettingsRoundTripAndStayTolerant() throws {
        var settings = ArtifactSettings()
        settings.prompt.extraRules = "one"
        settings.prompt.setRule("size", enabled: false, text: nil)
        settings.prompt.template = "T {{REQUEST}}"
        let back = try JSONDecoder().decode(ArtifactSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back, settings)

        let old = try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"maxOutputKB":40}"#.utf8))
        XCTAssertTrue(old.prompt.isDefault, "a setting saved before prompts existed has the built-in prompts")
        let broken = try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"prompt":{"rules":"nonsense","template":42,"extraRules":"x"}}"#.utf8))
        XCTAssertEqual(broken.prompt.extraRules, "x", "one bad field does not reset the rest")
        XCTAssertNil(broken.prompt.template)
        XCTAssertTrue(broken.prompt.rules.isEmpty)
    }

    func testRuleOverridesThatChangeNothingAreNotKept() {
        var config = ArtifactPromptSettings()
        config.setRule("size", enabled: true, text: "  ")
        XCTAssertTrue(config.rules.isEmpty)
        XCTAssertTrue(config.isDefault)
        config.setRule("size", enabled: false, text: nil)
        XCTAssertFalse(config.isDefault)
        XCTAssertTrue(config.changesExternalPrompt)
        XCTAssertFalse(config.changesInAppPrompt)
    }

    func testBulletsNormalizeLines() {
        XCTAssertEqual(ArtifactPrompts.bullets("a\n  \n- b\n  c  "), "- a\n- b\n- c")
        XCTAssertEqual(ArtifactPrompts.bullets("  \n"), "")
    }
}
