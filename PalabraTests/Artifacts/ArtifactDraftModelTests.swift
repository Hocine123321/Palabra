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

    private func makeEnvironment() async -> (AppEnvironment, MockAIClient) {
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
}
