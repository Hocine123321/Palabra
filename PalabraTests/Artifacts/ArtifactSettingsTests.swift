import XCTest
@testable import Palabra

final class ArtifactSettingsTests: XCTestCase {
    func testDefaults() {
        let s = ArtifactSettings.default
        XCTAssertEqual(s.maxOutputKB, 20, "the user's decision: the in-app AI writes 20 KB unless the person raises it")
        XCTAssertEqual(s.outputBytes, 20_480)
        XCTAssertTrue(s.allowAppArtifacts)
        XCTAssertEqual(s.defaultFormat, .auto)
    }

    func testRoundTrip() throws {
        var s = ArtifactSettings()
        s.maxOutputKB = 96
        s.allowAppArtifacts = false
        s.defaultFormat = .page
        let back = try JSONDecoder().decode(ArtifactSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testDecodingIsTolerant() throws {
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data("{}".utf8)), .default)
        let s = try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"maxOutputKB":"lots","defaultFormat":"from-the-future","allowAppArtifacts":false}"#.utf8))
        XCTAssertEqual(s.maxOutputKB, 20, "an unreadable size falls back to the default")
        XCTAssertEqual(s.defaultFormat, .auto)
        XCTAssertFalse(s.allowAppArtifacts)
    }

    func testSizeIsClampedOnDecode() throws {
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"maxOutputKB":9999}"#.utf8)).maxOutputKB, 128)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"maxOutputKB":-5}"#.utf8)).maxOutputKB, 8)
    }

    func testSettingsStorePersists() {
        let defaults = UserDefaults(suiteName: "ArtifactSettingsTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.artifactSettings, .default)
        var s = ArtifactSettings()
        s.maxOutputKB = 64
        store.artifactSettings = s
        XCTAssertEqual(SettingsStore(defaults: defaults).artifactSettings.maxOutputKB, 64)
    }

    // MARK: budget

    func testBudgetBounds() {
        XCTAssertEqual(ArtifactOutputBudget.clampedKB(1), 8)
        XCTAssertEqual(ArtifactOutputBudget.clampedKB(500), 128)
        XCTAssertEqual(ArtifactOutputBudget.bytes(forKB: 128), 131_072)
        XCTAssertEqual(ArtifactLimits.maxPayloadBytes, 2_097_152, "storage must accept the largest external page: 2 MB")
        XCTAssertGreaterThanOrEqual(ArtifactLimits.maxPayloadBytes, ArtifactOutputBudget.bytes(forKB: ArtifactOutputBudget.maxKB))
    }

    func testTheTwoSizeRanges() {
        // In-app AI: 8 to 128 KB, 20 by default. External AI: 128 KB to 2 MB.
        XCTAssertEqual(ArtifactOutputBudget.minKB, 8)
        XCTAssertEqual(ArtifactOutputBudget.maxKB, 128)
        XCTAssertEqual(ArtifactOutputBudget.defaultKB, 20)
        XCTAssertEqual(ArtifactOutputBudget.externalMinKB, 128)
        XCTAssertEqual(ArtifactOutputBudget.externalMaxKB, 2048)
        XCTAssertEqual(ArtifactOutputBudget.storageMaxBytes, 2 * 1024 * 1024)
        XCTAssertEqual(ArtifactOutputBudget.externalMinKB, ArtifactOutputBudget.maxKB, "the ranges meet: the in-app maximum is where the external range starts")
    }

    func testExternalCapDefaultsToTwoMegabytesAndIsClamped() throws {
        XCTAssertEqual(ArtifactSettings.default.externalMaxKB, 2048)
        XCTAssertEqual(ArtifactSettings.default.externalBytes, 2_097_152)
        XCTAssertEqual(ArtifactOutputBudget.clampedExternalKB(1), 128)
        XCTAssertEqual(ArtifactOutputBudget.clampedExternalKB(999_999), 2048)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"externalMaxKB":640}"#.utf8)).externalMaxKB, 640)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"externalMaxKB":5}"#.utf8)).externalMaxKB, 128)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data(#"{"externalMaxKB":"big"}"#.utf8)).externalMaxKB, 2048)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSettings.self, from: Data("{}".utf8)).externalMaxKB, 2048, "settings saved before this existed")
    }

    func testTheTwoCapsAreIndependent() throws {
        var s = ArtifactSettings()
        s.externalMaxKB = 512
        let back = try JSONDecoder().decode(ArtifactSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.externalMaxKB, 512)
        XCTAssertEqual(back.maxOutputKB, 20)
    }

    func testExternalSliderStepsLandOnTheEnds() {
        let step = ArtifactOutputBudget.externalStepKB
        XCTAssertEqual((ArtifactOutputBudget.externalMaxKB - ArtifactOutputBudget.externalMinKB) % step, 0)
        XCTAssertEqual((ArtifactOutputBudget.externalDefaultKB - ArtifactOutputBudget.externalMinKB) % step, 0)
    }

    func testTheDefaultIsInsideTheSliderRangeAndOnAStep() {
        let d = ArtifactOutputBudget.defaultKB
        XCTAssertTrue((ArtifactOutputBudget.minKB...ArtifactOutputBudget.maxKB).contains(d))
        XCTAssertEqual((d - ArtifactOutputBudget.minKB) % ArtifactOutputBudget.stepKB, 0, "the slider can land exactly on the default")
    }

    func testTokensGrowWithSizeAndCoverTheBytes() {
        var last = 0
        for kb in stride(from: ArtifactOutputBudget.minKB, through: ArtifactOutputBudget.maxKB, by: ArtifactOutputBudget.stepKB) {
            let tokens = ArtifactOutputBudget.tokens(forKB: kb)
            XCTAssertGreaterThan(tokens, last)
            XCTAssertGreaterThanOrEqual(Double(tokens) * ArtifactOutputBudget.bytesPerToken, Double(kb * 1024))
            last = tokens
        }
    }

    func testReachableKBIsTheInverseOfTokens() {
        for kb in [8, 20, 64, 128] {
            XCTAssertGreaterThanOrEqual(ArtifactOutputBudget.reachableKB(tokenLimit: ArtifactOutputBudget.tokens(forKB: kb)), kb)
        }
        XCTAssertEqual(ArtifactOutputBudget.reachableKB(tokenLimit: 0), 0)
        XCTAssertLessThan(ArtifactOutputBudget.reachableKB(tokenLimit: 8192), 24)
    }

    // MARK: Gemini output cap

    private func model(limit: Int?) -> AIModel {
        AIModel(id: "models/m", displayName: "M", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: limit)
    }

    func testGeminiKeepsTheOldCapWhenNothingIsRequested() {
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: 65_536), requested: nil), 8192)
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: 4096), requested: nil), 4096)
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: nil), requested: nil), 8192)
    }

    func testGeminiRaisesTheCapUpToTheModelLimit() {
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: 65_536), requested: 44_000), 44_000)
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: 16_000), requested: 44_000), 16_000)
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: nil), requested: 44_000), 44_000)
    }

    func testARequestBelowTheOldCapNeverLowersIt() {
        XCTAssertEqual(GeminiClient.structuredMaxTokens(model: model(limit: 65_536), requested: 3000), 8192)
    }

    func testTimeoutGrowsWithTheOutputBudgetButStaysBounded() {
        XCTAssertEqual(GeminiClient.structuredTimeout(maxTokens: 8192), 90, "other callers keep exactly the old 90 seconds")
        XCTAssertEqual(GeminiClient.structuredTimeout(maxTokens: 1000), 90)
        XCTAssertEqual(GeminiClient.structuredTimeout(maxTokens: 20_000), 230, accuracy: 0.01)
        XCTAssertGreaterThan(GeminiClient.structuredTimeout(maxTokens: ArtifactOutputBudget.tokens(forKB: 128)), 300 - 1)
        XCTAssertEqual(GeminiClient.structuredTimeout(maxTokens: 1_000_000), 300, "bounded")
    }

    // MARK: lint and prompt

    func testLintHonoursTheSetting() {
        let body = String(repeating: "a", count: 30_000)
        let html = "<html>" + body + "</html>"
        XCTAssertEqual(ArtifactHTMLLint.check(html, maxBytes: 20 * 1024), .failure(.tooLarge))
        XCTAssertEqual(ArtifactHTMLLint.check(html, maxBytes: 64 * 1024), .success(html))
    }

    func testLintAcceptsExactlyTheLimitAndRejectsOneMore() {
        let limit = 8 * 1024
        let fit = "<html>" + String(repeating: "a", count: limit - 13) + "</html>"
        XCTAssertEqual(fit.utf8.count, limit)
        XCTAssertEqual(ArtifactHTMLLint.check(fit, maxBytes: limit), .success(fit))
        XCTAssertEqual(ArtifactHTMLLint.check(fit + "a", maxBytes: limit), .failure(.tooLarge))
    }

    func testLintNeverExceedsTheStorageCeiling() {
        let html = "<html>" + String(repeating: "a", count: ArtifactLimits.maxPayloadBytes) + "</html>"
        XCTAssertEqual(ArtifactHTMLLint.check(html, maxBytes: .max), .failure(.tooLarge))
    }

    func testPromptStatesTheChosenSize() {
        let registry = CapabilityRegistry([makeCapability("library.words", .read)])
        let big = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app], maxKB: 100)
        XCTAssertTrue(big.contains("At most 100 KB"))
        XCTAssertFalse(big.contains("At most 128 KB"))
        let capped = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app], maxKB: 5000)
        XCTAssertTrue(capped.contains("At most 128 KB"))
        let standard = ArtifactPrompts.systemInstruction(registry: registry, language: .english, allowedKinds: [.spec, .app])
        XCTAssertTrue(standard.contains("At most 20 KB"), "with no size given, the in-app default applies")
    }

    // MARK: generator wiring

    private final class BudgetRecorder: AIClient, @unchecked Sendable {
        var seenTokens: [Int?] = []
        var seenPrompts: [String] = []
        var reply = ""
        func listModels(apiKey: String) async -> Result<[AIModel], AIError> { .success([]) }
        func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> { .failure(.malformedResponse) }
        func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> { .failure(.malformedResponse) }
        func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> { .failure(.malformedResponse) }
        func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
            seenTokens.append(ArtifactOutputBudget.requestedTokens)
            seenPrompts.append(prompt)
            return .success(reply)
        }
        func generateJSON(prompt: String, image: AIImage, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> { .failure(.malformedResponse) }
        func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> { .failure(.malformedResponse) }
    }

    func testGeneratorSendsTheBudgetAndOnlyForItsOwnCall() async {
        let client = BudgetRecorder()
        client.reply = #"{"kind":"spec","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + #"{"blocks":[{"type":"text","text":"x"}]}"# + "\n---END---"
        let model = AIModel(id: "models/m", displayName: "M", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 65_536)
        var generator = ArtifactGenerator(ai: client, registry: CapabilityRegistry([makeCapability("library.words", .read)]))
        generator.maxOutputKB = 100
        _ = await generator.create(request: "a table of weekdays", apiKey: "k", model: model)
        XCTAssertEqual(client.seenTokens, [ArtifactOutputBudget.tokens(forKB: 100)])
        XCTAssertNil(ArtifactOutputBudget.requestedTokens, "the budget must not leak outside the generator call")
    }

    func testGeneratorLintsAppsAgainstTheSetting() async {
        let client = BudgetRecorder()
        let html = "<html><body>" + String(repeating: "a", count: 30_000) + "</body></html>"
        client.reply = #"{"kind":"app","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + html + "\n---END---"
        let model = AIModel(id: "models/m", displayName: "M", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 65_536)
        var small = ArtifactGenerator(ai: client, registry: CapabilityRegistry([]), allowedKinds: [.spec, .app])
        small.maxOutputKB = 20
        guard case .failure = await small.create(request: "big app", apiKey: "k", model: model) else { return XCTFail("30 KB must not fit in 20 KB") }
        XCTAssertEqual(client.seenPrompts.count, 2, "one retry, no more")
        XCTAssertTrue(client.seenPrompts[1].contains("larger than 20 KB"), "the retry names the person's real limit")
        client.seenPrompts = []
        var large = small
        large.maxOutputKB = 64
        guard case .success(let draft) = await large.create(request: "big app", apiKey: "k", model: model) else { return XCTFail("30 KB fits in 64 KB") }
        XCTAssertEqual(draft.kind, .app)
    }
}
