import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class ArtifactDraftModelTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!
    private var artifacts: SwiftDataArtifactRepository!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        keychain = KeychainStore()
        keychain.delete()
        artifacts = SwiftDataArtifactRepository.inMemory()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    private func makeEnvironment(withKey: Bool = true) async -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "adm-\(UUID().uuidString)") ?? .standard),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            artifactRepository: artifacts
        )
        guard withKey else { return (env, client) }
        env.saveAPIKey("test-api-key")
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
        return (env, client)
    }

    private func appReply(requests: String, html: String = "<html><body>hola</body></html>") -> String {
        #"{"kind":"app","title":"Practice","requests":\#(requests)}"# + "\n---PAYLOAD---\n\(html)\n---END---"
    }

    func testAppDraftNeedsApprovalThenSavesGrants() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: #"["library.words","storage.get"]"#))
        let model = ArtifactDraftModel(environment: env)
        model.request = "a practice app"
        await model.generate()
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.pending.map(\.name), ["library.words"])
        XCTAssertTrue(model.needsDecision)
        XCTAssertEqual(model.effectiveGrant, ["storage.get"])
        model.allowPending()
        XCTAssertFalse(model.needsDecision)
        XCTAssertEqual(model.effectiveGrant, ["library.words", "storage.get"])
        guard let id = model.save() else { return XCTFail("save failed: \(String(describing: model.saveError))") }
        XCTAssertEqual(artifacts.artifact(id: id)?.grantedNames, ["library.words"])
        XCTAssertEqual(artifacts.artifact(id: id)?.kind, .app)
    }

    func testChosenFormatIsSentButOnlyTheTypedRequestIsKept() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: "[]"))
        let model = ArtifactDraftModel(environment: env)
        model.request = "  a practice app  "
        model.format = .app
        await model.generate()
        XCTAssertEqual(client.generateJSONCalls.last?.prompt, ArtifactFormat.app.requestPrefix + "a practice app")
        guard let id = model.save() else { return XCTFail("save failed") }
        let version = artifacts.versions(artifactID: id).first
        XCTAssertEqual(version?.prompt, "a practice app")
    }

    func testAutoFormatSendsTheRequestUntouched() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: "[]"))
        let model = ArtifactDraftModel(environment: env)
        model.request = "a practice app"
        await model.generate()
        XCTAssertEqual(client.generateJSONCalls.last?.prompt, "a practice app")
    }

    func testOverlongRequestIsCutBeforeTheFormatLine() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: "[]"))
        let model = ArtifactDraftModel(environment: env)
        model.request = String(repeating: "x", count: ArtifactGeneratorLimits.maxRequestLength)
        model.format = .page
        await model.generate()
        let sent = client.generateJSONCalls.last?.prompt ?? ""
        XCTAssertTrue(sent.hasPrefix(ArtifactFormat.page.requestPrefix))
        XCTAssertEqual(sent.count, ArtifactFormat.page.requestPrefix.count + ArtifactDraftModel.maxInput)
    }

    func testDenyThenSaveStoresNoGrants() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: #"["library.words"]"#))
        let model = ArtifactDraftModel(environment: env)
        model.request = "a practice app"
        await model.generate()
        model.denyPending()
        XCTAssertFalse(model.needsDecision)
        XCTAssertEqual(model.effectiveGrant, [])
        guard let id = model.save() else { return XCTFail("save failed") }
        XCTAssertEqual(artifacts.artifact(id: id)?.grantedNames, [])
    }

    func testSpecDraftNeverAsksForApproval() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(#"{"kind":"spec","title":"T","requests":["library.words"]}"# + "\n---PAYLOAD---\n" + #"{"blocks":[{"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{}}}]}"# + "\n---END---")
        let model = ArtifactDraftModel(environment: env)
        model.request = "my words"
        await model.generate()
        XCTAssertEqual(model.phase, .preview)
        XCTAssertFalse(model.needsDecision)
    }

    func testUpdateGrantsAreUnionedAndOnlyTheDeltaIsPending() async {
        let (env, client) = await makeEnvironment()
        guard case .success(let artifact) = artifacts.create(title: "Practice", kind: .app, payload: Data("<html>1</html>".utf8), requested: ["library.words"], prompt: "p", now: Date()) else {
            return XCTFail("create failed")
        }
        artifacts.setGranted(artifactID: artifact.id, names: ["library.words"])
        client.generateJSONResult = .success(appReply(requests: #"["library.words","ai.generate"]"#))
        let model = ArtifactDraftModel(environment: env, mode: .update(artifactID: artifact.id))
        model.request = "add an AI conversation"
        await model.generate()
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.pending.map(\.name), ["ai.generate"])
        model.allowPending()
        XCTAssertNotNil(model.save())
        XCTAssertEqual(artifacts.artifact(id: artifact.id)?.grantedNames, ["ai.generate", "library.words"])
        XCTAssertEqual(artifacts.artifact(id: artifact.id)?.currentVersion, 2)
    }

    func testUpdateWithoutNewCapabilitiesKeepsGrantsAndDoesNotAsk() async {
        let (env, client) = await makeEnvironment()
        guard case .success(let artifact) = artifacts.create(title: "Practice", kind: .app, payload: Data("<html>1</html>".utf8), requested: ["library.words"], prompt: "p", now: Date()) else {
            return XCTFail("create failed")
        }
        artifacts.setGranted(artifactID: artifact.id, names: ["library.words"])
        client.generateJSONResult = .success(appReply(requests: #"["library.words"]"#, html: "<html>2</html>"))
        let model = ArtifactDraftModel(environment: env, mode: .update(artifactID: artifact.id))
        model.request = "make it blue"
        await model.generate()
        XCTAssertFalse(model.needsDecision)
        XCTAssertEqual(model.effectiveGrant, ["library.words"])
        XCTAssertNotNil(model.save())
        XCTAssertEqual(artifacts.artifact(id: artifact.id)?.grantedNames, ["library.words"])
    }

    func testGeneratorIsOfferedBothKinds() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(appReply(requests: "[]"))
        let model = ArtifactDraftModel(environment: env)
        model.request = "a practice app"
        await model.generate()
        let instruction = client.generateJSONCalls.first?.systemInstruction ?? ""
        XCTAssertTrue(instruction.contains("palabra.call"))
        XCTAssertTrue(instruction.contains("ai.generate"))
    }

    // MARK: External AI export and import

    func testExportPromptForCreateDescribesAnHTMLPageAndIncludesTheRequest() async {
        let (env, _) = await makeEnvironment(withKey: false)
        let model = ArtifactDraftModel(environment: env)
        model.format = .app
        model.request = "verb trainer"
        let prompt = model.exportPrompt() ?? ""
        XCTAssertTrue(prompt.contains("verb trainer"))
        XCTAssertTrue(prompt.contains("self-contained HTML page"), "it asks for an HTML page")
        XCTAssertFalse(prompt.lowercased().contains("code fence"), "it does not dictate how a full AI app delivers the page")
        XCTAssertFalse(prompt.contains("---PAYLOAD---"), "no envelope for the other AI to get wrong")
        XCTAssertFalse(prompt.contains("---END---"))
        XCTAssertFalse(prompt.contains("FORMAT:"), "the Gemini format picker does not apply to another AI")
    }

    func testExportPromptForUpdateIncludesTheCurrentPage() async {
        let (env, _) = await makeEnvironment(withKey: false)
        guard case .success(let artifact) = artifacts.create(title: "Practice", kind: .app, payload: Data("<html><body>stored page</body></html>".utf8), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        let model = ArtifactDraftModel(environment: env, mode: .update(artifactID: artifact.id))
        model.request = "add a score"
        XCTAssertTrue(model.canUseExternalAI)
        let prompt = model.exportPrompt() ?? ""
        XCTAssertTrue(prompt.contains("CURRENT PAGE:"))
        XCTAssertTrue(prompt.contains("stored page"))
        XCTAssertTrue(prompt.contains("add a score"))
        XCTAssertTrue(prompt.contains("TITLE: Practice"))
    }

    /// A table or chart (spec) is JSON blocks, not a page: another AI answering with HTML could not replace it, so no prompt is offered.
    func testASpecArtifactCannotBeUpdatedThroughAnotherAI() async {
        let (env, _) = await makeEnvironment(withKey: false)
        guard case .success(let artifact) = artifacts.create(title: "Table", kind: .spec, payload: Data(#"{"blocks":[{"type":"text","text":"x"}]}"#.utf8), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        let model = ArtifactDraftModel(environment: env, mode: .update(artifactID: artifact.id))
        model.request = "add a column"
        XCTAssertFalse(model.canUseExternalAI)
        XCTAssertNil(model.exportPrompt())
    }

    func testThePromptCarriesThePersonsExternalCap() async {
        let (env, _) = await makeEnvironment(withKey: false)
        env.artifactSettings.externalMaxKB = 640
        let model = ArtifactDraftModel(environment: env)
        model.request = "verb trainer"
        XCTAssertTrue((model.exportPrompt() ?? "").contains("At most 640 KB"))
    }

    func testAnImportFollowsThePersonsExternalCap() async {
        let (env, _) = await makeEnvironment(withKey: false)
        env.artifactSettings.externalMaxKB = 128
        let model = ArtifactDraftModel(environment: env)
        model.importExternal("<html><head><title>Big</title></head><body>" + String(repeating: "a", count: 200 * 1024) + "</body></html>")
        guard case .failed = model.phase else { return XCTFail("200 KB must not fit a 128 KB cap, got \(model.phase)") }
        env.artifactSettings.externalMaxKB = 512
        model.dismissFailure()
        model.importExternal("<html><head><title>Big</title></head><body>" + String(repeating: "a", count: 200 * 1024) + "</body></html>")
        XCTAssertEqual(model.phase, .preview)
    }

    func testCreatingAlwaysOffersTheExternalRoute() async {
        let (env, _) = await makeEnvironment(withKey: false)
        XCTAssertTrue(ArtifactDraftModel(environment: env).canUseExternalAI)
    }

    func testAPlainHTMLPageIsImportedAsAnAppWithItsTitleAndCalls() async {
        let (env, client) = await makeEnvironment(withKey: false)
        let model = ArtifactDraftModel(environment: env)
        let page = "Here you go!\n```html\n<!DOCTYPE html><html><head><title>Verb Trainer</title></head><body><script>palabra.call(\"library.words\", {})</script></body></html>\n```"
        model.importExternal(page)
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.draft?.kind, .app)
        XCTAssertEqual(model.draft?.title, "Verb Trainer")
        XCTAssertEqual(model.draft?.requests, ["library.words"])
        XCTAssertTrue(client.generateJSONCalls.isEmpty)
    }

    func testAPageOverTheInAppCapIsImportedAndSaved() async {
        let (env, _) = await makeEnvironment(withKey: false)
        env.artifactSettings.externalMaxKB = ArtifactOutputBudget.externalMaxKB
        let model = ArtifactDraftModel(environment: env)
        // 600 KB: far above Gemini's 128 KB maximum, inside the 2 MB an external page may be.
        model.importExternal("<html><head><title>Big</title></head><body>" + String(repeating: "a", count: 600_000) + "</body></html>")
        XCTAssertEqual(model.phase, .preview)
        XCTAssertNotNil(model.save(), "storage accepts what the import accepted")
    }

    func testExportPromptNilWhenRequestTooShort() async {
        let (env, _) = await makeEnvironment(withKey: false)
        let model = ArtifactDraftModel(environment: env)
        model.request = "ab"
        XCTAssertNil(model.exportPrompt())
    }

    func testImportWorksWithoutAnAPIKeyAndMakesNoAICalls() async {
        let (env, client) = await makeEnvironment(withKey: false)
        let model = ArtifactDraftModel(environment: env)
        model.importExternal(appReply(requests: #"["library.words"]"#))
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(model.draft?.kind, .app)
        XCTAssertTrue(client.generateJSONCalls.isEmpty)
    }

    func testImportKeepsTheRequestAsPromptAndFallsBackToALabel() async {
        let (env, _) = await makeEnvironment(withKey: false)
        let typed = ArtifactDraftModel(environment: env)
        typed.request = "a verb trainer"
        typed.importExternal(appReply(requests: "[]"))
        XCTAssertEqual(typed.draft?.prompt, "a verb trainer")
        let untyped = ArtifactDraftModel(environment: env)
        untyped.importExternal(appReply(requests: "[]"))
        XCTAssertEqual(untyped.draft?.prompt, ArtifactDraftModel.importedLabel)
    }

    func testImportFailureShowsFailedAndRetryReplaysWithoutAnAICall() async {
        let (env, client) = await makeEnvironment()
        let model = ArtifactDraftModel(environment: env)
        model.importExternal("hello")
        guard case .failed(.malformedEnvelope) = model.phase else { return XCTFail("expected a malformed envelope, got \(model.phase)") }
        model.dismissFailure()
        XCTAssertEqual(model.phase, .input)
        await model.retry()
        guard case .failed = model.phase else { return XCTFail("expected the failure again") }
        XCTAssertTrue(client.generateJSONCalls.isEmpty)
    }

    func testUpdateImportKeepsKindAndSavesANewVersion() async {
        let (env, _) = await makeEnvironment(withKey: false)
        guard case .success(let artifact) = artifacts.create(title: "Practice", kind: .app, payload: Data("<html></html>".utf8), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        let model = ArtifactDraftModel(environment: env, mode: .update(artifactID: artifact.id))
        let spec = #"{"kind":"spec","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + #"{"blocks":[{"type":"text","text":"x"}]}"# + "\n---END---"
        model.importExternal(spec)
        guard case .failed(.malformedEnvelope) = model.phase else { return XCTFail("a spec must not replace an app, got \(model.phase)") }
        model.importExternal(appReply(requests: "[]", html: "<html><body>new</body></html>"))
        XCTAssertEqual(model.phase, .preview)
        XCTAssertNotNil(model.save())
        XCTAssertEqual(artifacts.artifact(id: artifact.id)?.currentVersion, 2)
        XCTAssertEqual(artifacts.artifact(id: artifact.id)?.title, "Practice")
    }

    func testImportAsksApprovalForNewCapabilities() async {
        let (env, _) = await makeEnvironment(withKey: false)
        let model = ArtifactDraftModel(environment: env)
        model.importExternal(appReply(requests: #"["library.words"]"#))
        XCTAssertTrue(model.needsDecision)
        XCTAssertEqual(model.pending.map(\.name), ["library.words"])
    }
}
