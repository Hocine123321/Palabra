import XCTest
import SwiftData
@testable import Palabra

final class OpenAICompatibleClientTests: XCTestCase {
    private var groq: OpenAICompatibleClient!
    private var openRouter: OpenAICompatibleClient!
    private let groqModel = AIModel(id: "llama-3.3-70b-versatile", displayName: "llama", description: nil, inputTokenLimit: nil, outputTokenLimit: 8192, provider: .groq, acceptsImages: false)
    private let routerModel = AIModel(id: "openai/gpt-4o-mini", displayName: "gpt", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .openRouter, acceptsImages: true)

    override func setUp() {
        super.setUp()
        groq = OpenAICompatibleClient(provider: .groq, session: MockURLProtocol.session())
        openRouter = OpenAICompatibleClient(provider: .openRouter, session: MockURLProtocol.session())
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func completion(_ text: String, finish: String = "stop") -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": text], "finish_reason": finish]]])
    }

    private func bodyJSON(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func testStructuredCallSendsKeyModelSchemaAndJSONMode() async {
        let seen = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { request in seen.value = request; return (200, self.completion("```json\n{\"ok\":true}\n```")) }
        let schema: [String: Any] = ["type": "OBJECT", "properties": ["ok": ["type": "BOOLEAN"]]]
        let result = await groq.generateJSON(prompt: "hello", systemInstruction: "Be brief.", schema: schema, apiKey: " gsk-1 ", model: groqModel, temperature: 0.2)
        XCTAssertEqual(try? result.get(), "{\"ok\":true}", "a code fence around the JSON is removed")
        let request = try! XCTUnwrap(seen.value)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk-1")
        let body = bodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "llama-3.3-70b-versatile")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertEqual(body["max_tokens"] as? Int, 8192)
        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        let system = messages.first?["content"] as? String ?? ""
        XCTAssertTrue(system.contains("Be brief."))
        XCTAssertTrue(system.contains("BOOLEAN"), "the schema is described to the model in words")
        XCTAssertEqual(messages.last?["content"] as? String, "hello", "the real prompt is sent, not a placeholder")
    }

    func testOpenRouterSendsAttributionHeaders() async {
        let seen = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { request in seen.value = request; return (200, self.completion("hi")) }
        _ = await openRouter.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "or-1", model: routerModel, temperature: 0)
        XCTAssertEqual(seen.value?.url?.host, "openrouter.ai")
        XCTAssertEqual(seen.value?.value(forHTTPHeaderField: "X-Title"), "Palabra")
        XCTAssertNil(bodyJSON(seen.value!)["response_format"], "no schema: no JSON mode")
    }

    func testPhotoIsSentAsDataURL() async {
        let seen = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { request in seen.value = request; return (200, self.completion("x")) }
        let image = AIImage(data: Data([1, 2, 3]), mimeType: "image/jpeg")
        _ = await openRouter.generateJSON(prompt: "read it", image: image, systemInstruction: "s", schema: nil, apiKey: "k", model: routerModel, temperature: 0)
        let messages = bodyJSON(seen.value!)["messages"] as? [[String: Any]] ?? []
        let parts = messages.last?["content"] as? [[String: Any]] ?? []
        let url = (parts.first?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url, "data:image/jpeg;base64,AQID")
        XCTAssertEqual(parts.last?["text"] as? String, "read it")
    }

    func testRetriesWithoutJSONModeWhenTheModelRefusesIt() async {
        let calls = Box<[[String: Any]]>([])
        MockURLProtocol.handler = { request in
            calls.value.append(self.bodyJSON(request))
            if calls.value.count == 1 {
                let err = try! JSONSerialization.data(withJSONObject: ["error": ["message": "response_format json_object is not supported by this model", "code": 400]])
                return (400, err)
            }
            return (200, self.completion("{\"a\":1}"))
        }
        let schema: [String: Any] = ["type": "OBJECT"]
        let result = await groq.generateJSON(prompt: "p", systemInstruction: "s", schema: schema, apiKey: "k", model: groqModel, temperature: 0)
        XCTAssertEqual(try? result.get(), "{\"a\":1}")
        XCTAssertEqual(calls.value.count, 2)
        XCTAssertNotNil(calls.value[0]["response_format"])
        XCTAssertNil(calls.value[1]["response_format"])
    }

    func testErrorsAreMapped() async {
        func status(_ code: Int, _ message: String) async -> AIError? {
            MockURLProtocol.handler = { _ in (code, try! JSONSerialization.data(withJSONObject: ["error": ["message": message]])) }
            if case .failure(let e) = await groq.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "k", model: groqModel, temperature: 0) { return e }
            return nil
        }
        let invalid = await status(401, "Invalid API Key")
        XCTAssertEqual(invalid, .invalidAPIKey)
        let credits = await status(402, "Insufficient credits")
        XCTAssertEqual(credits, .quotaExhausted)
        let daily = await status(429, "Rate limit reached for model in organization on tokens per day (TPD)")
        XCTAssertEqual(daily, .quotaExhausted)
        let perMinute = await status(429, "Rate limit reached on requests per minute (RPM)")
        XCTAssertEqual(perMinute, .rateLimited)
        let gone = await status(404, "The model does not exist")
        XCTAssertEqual(gone, .modelUnavailable("llama-3.3-70b-versatile"))
        let server = await status(503, "overloaded")
        XCTAssertEqual(server, .serverError(503))
    }

    func testRetryHintIsReadFromRetryAfter() async {
        // The mock protocol sends no headers, so the mapping is checked directly.
        let error = groq.mapError(status: 429, message: "slow down", retryAfter: "7", model: nil)
        XCTAssertEqual(error, .rateLimited)
        XCTAssertEqual(groq.takeRetryHint(), 7)
        XCTAssertNil(groq.takeRetryHint(), "the hint is read once")
    }

    func testTruncatedAndBlockedReplies() async {
        MockURLProtocol.handler = { _ in (200, self.completion("half", finish: "length")) }
        let cut = await groq.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "k", model: groqModel, temperature: 0)
        if case .failure(let e) = cut { XCTAssertEqual(e, .truncated) } else { XCTFail("expected truncated") }
        MockURLProtocol.handler = { _ in (200, self.completion("", finish: "content_filter")) }
        let blocked = await groq.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "k", model: groqModel, temperature: 0)
        if case .failure(.blocked) = blocked {} else { XCTFail("expected blocked") }
    }

    func testGroqModelListDropsSpeechAndGuardModels() async {
        MockURLProtocol.handler = { _ in
            let list: [[String: Any]] = [
                ["id": "llama-3.3-70b-versatile", "context_window": 131072, "max_completion_tokens": 32768, "active": true],
                ["id": "whisper-large-v3", "active": true],
                ["id": "meta-llama/llama-guard-4-12b", "active": true],
                ["id": "playai-tts", "active": true],
                ["id": "meta-llama/llama-4-scout-17b-16e-instruct", "active": true],
            ]
            return (200, try! JSONSerialization.data(withJSONObject: ["data": list]))
        }
        guard case .success(let models) = await groq.listModels(apiKey: "k") else { return XCTFail("expected a list") }
        XCTAssertEqual(Set(models.map(\.id)), ["llama-3.3-70b-versatile", "meta-llama/llama-4-scout-17b-16e-instruct"])
        XCTAssertTrue(models.allSatisfy { $0.provider == .groq })
        XCTAssertEqual(models.first { $0.id == "llama-3.3-70b-versatile" }?.outputTokenLimit, 32768)
        XCTAssertEqual(models.first { $0.id.contains("scout") }?.acceptsImages, true)
    }

    func testOpenRouterChecksTheKeyBecauseItsModelListIsPublic() async {
        let paths = Box<[String]>([])
        MockURLProtocol.handler = { request in
            paths.value.append(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/key") == true { return (401, Data("{\"error\":{\"message\":\"No auth credentials found\"}}".utf8)) }
            return (200, Data("{\"data\":[]}".utf8))
        }
        let result = await openRouter.listModels(apiKey: "wrong")
        if case .failure(let e) = result { XCTAssertEqual(e, .invalidAPIKey) } else { XCTFail("a wrong key must be rejected") }
        XCTAssertFalse(paths.value.contains { $0.hasSuffix("/models") }, "the list is not even asked for")
    }

    func testOpenRouterListKeepsTextModelsAndMarksFreeOnes() async {
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/key") == true { return (200, Data("{\"data\":{}}".utf8)) }
            let list: [[String: Any]] = [
                ["id": "openai/gpt-4o-mini", "name": "OpenAI: GPT-4o mini", "context_length": 128000,
                 "architecture": ["input_modalities": ["text", "image"], "output_modalities": ["text"]],
                 "pricing": ["prompt": "0.00000015", "completion": "0.0000006"]],
                ["id": "some/image-maker", "name": "Image maker", "architecture": ["input_modalities": ["text"], "output_modalities": ["image"]]],
                ["id": "meta-llama/llama-3.3-70b-instruct:free", "name": "Llama 3.3 70B", "pricing": ["prompt": "0", "completion": "0"],
                 "architecture": ["input_modalities": ["text"], "output_modalities": ["text"]]],
            ]
            return (200, try! JSONSerialization.data(withJSONObject: ["data": list]))
        }
        guard case .success(let models) = await openRouter.listModels(apiKey: "ok") else { return XCTFail("expected a list") }
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.first { $0.id == "openai/gpt-4o-mini" }?.acceptsImages, true)
        XCTAssertEqual(models.first { $0.id.hasSuffix(":free") }?.acceptsImages, false)
        XCTAssertTrue(models.first { $0.id.hasSuffix(":free") }?.displayName.contains("free") == true)
    }

    func testSpeechIsNotSupported() async {
        let result = await groq.synthesizeSpeech("hola", apiKey: "k", model: groqModel)
        if case .failure = result {} else { XCTFail("Groq/OpenRouter cannot synthesize speech here") }
    }
}

final class RoutingAIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testEachModelGoesToItsOwnProvider() async {
        let hosts = Box<[String]>([])
        MockURLProtocol.handler = { request in
            hosts.value.append(request.url?.host ?? "")
            if request.url?.host == "generativelanguage.googleapis.com" {
                let body: [String: Any] = ["candidates": [["content": ["parts": [["text": "{}"]]]]]]
                return (200, try! JSONSerialization.data(withJSONObject: body))
            }
            let body: [String: Any] = ["choices": [["message": ["content": "{}"], "finish_reason": "stop"]]]
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        let router = RoutingAIClient(session: MockURLProtocol.session())
        let gemini = AIModel(id: "models/gemini-2.5-flash", displayName: "g", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
        let groq = AIModel(id: "llama-3.3-70b-versatile", displayName: "l", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .groq)
        let openRouter = AIModel(id: "openai/gpt-4o-mini", displayName: "o", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .openRouter)
        for model in [gemini, groq, openRouter] {
            _ = await router.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "k", model: model, temperature: 0)
        }
        XCTAssertEqual(hosts.value, ["generativelanguage.googleapis.com", "api.groq.com", "openrouter.ai"])
    }

    func testModelListFollowsTheCataloguesProviderOrTheActiveOne() async {
        let hosts = Box<[String]>([])
        MockURLProtocol.handler = { request in
            hosts.value.append(request.url?.host ?? "")
            return (200, Data("{\"data\":[],\"models\":[]}".utf8))
        }
        let router = RoutingAIClient(session: MockURLProtocol.session(), active: .groq)
        _ = await router.listModels(apiKey: "k")
        _ = await AIProviderContext.$listing.withValue(.gemini) { await router.listModels(apiKey: "k") }
        router.activeProvider = .gemini
        _ = await router.listModels(apiKey: "k")
        XCTAssertEqual(hosts.value, ["api.groq.com", "generativelanguage.googleapis.com", "generativelanguage.googleapis.com"])
    }
}

final class ProviderSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "dev.palabra.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testGeminiKeepsItsOriginalStorageNames() {
        XCTAssertEqual(AIProvider.gemini.keychainAccount, "api-key")
        XCTAssertEqual(AIProvider.gemini.backupKeychainAccount, "api-key-fallback")
        XCTAssertEqual(AIProvider.gemini.selectedModelKey, "selectedModelID")
        XCTAssertEqual(AIProvider.gemini.catalogueFileName, "ModelCatalogue.json")
    }

    func testEveryProviderHasItsOwnSlots() {
        let all = AIProvider.allCases
        XCTAssertEqual(Set(all.map(\.keychainAccount)).count, all.count)
        XCTAssertEqual(Set(all.map(\.backupKeychainAccount)).count, all.count)
        XCTAssertEqual(Set(all.map(\.selectedModelKey)).count, all.count)
        XCTAssertEqual(Set(all.map(\.catalogueFileName)).count, all.count)
    }

    func testProviderAndModelChoicePersistPerProvider() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.aiProvider, .gemini, "an install from before providers is on Gemini")
        store.setSelectedModelID("models/gemini-2.5-flash", for: .gemini)
        store.setSelectedModelID("llama-3.3-70b-versatile", for: .groq)
        store.aiProvider = .groq
        let again = SettingsStore(defaults: defaults)
        XCTAssertEqual(again.aiProvider, .groq)
        XCTAssertEqual(again.selectedModelID(for: .groq), "llama-3.3-70b-versatile")
        XCTAssertEqual(again.selectedModelID, "models/gemini-2.5-flash", "the old accessor is still Gemini's")
        XCTAssertNil(again.selectedModelID(for: .openRouter))
    }

    func testAModelSavedBeforeProvidersDecodesAsGemini() throws {
        let old = #"{"id":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash"}"#
        let model = try JSONDecoder().decode(AIModel.self, from: Data(old.utf8))
        XCTAssertNil(model.provider)
        XCTAssertEqual(model.resolvedProvider, .gemini)
    }

    func testProviderModelPickerPrefersAStrongPaidModel() {
        func m(_ id: String, _ p: AIProvider) -> AIModel { AIModel(id: id, displayName: id, description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: p) }
        let groq = [m("allam-2-7b", .groq), m("llama-3.3-70b-versatile", .groq)]
        XCTAssertEqual(DefaultModelPicker.pick(from: groq)?.id, "llama-3.3-70b-versatile")
        let router = [m("meta-llama/llama-3.3-70b-instruct:free", .openRouter), m("openai/gpt-4o-mini", .openRouter)]
        XCTAssertEqual(DefaultModelPicker.pick(from: router)?.id, "openai/gpt-4o-mini")
        XCTAssertEqual(DefaultModelPicker.pick(from: [m("x/y", .openRouter)])?.id, "x/y")
    }
}

@MainActor
final class ProviderEnvironmentTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        defaults = UserDefaults(suiteName: "provider-env-\(UUID().uuidString)")
    }

    private func makeEnvironment(ai: AIClient = MockAIClient()) -> AppEnvironment {
        func key(_ name: String) -> KeychainStore { KeychainStore(account: "provider-test-\(name)-\(UUID().uuidString)") }
        func cache() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
        return AppEnvironment(
            ai: ai,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: cache()),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: cache()),
            keychain: key("gemini"),
            settings: SettingsStore(defaults: defaults),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            fallbackKeychain: key("gemini-backup"),
            providerKeychains: [.openRouter: key("or"), .groq: key("groq")],
            providerBackupKeychains: [.openRouter: key("or-b"), .groq: key("groq-b")],
            providerCatalogues: [
                .openRouter: ModelCatalogue(cacheFileName: "or.json", filter: ProviderModelFilter.apply, cacheDirectory: cache(), provider: .openRouter),
                .groq: ModelCatalogue(cacheFileName: "groq.json", filter: ProviderModelFilter.apply, cacheDirectory: cache(), provider: .groq),
            ]
        )
    }

    func testEachProviderKeepsItsOwnKeyAndModel() {
        let env = makeEnvironment()
        XCTAssertEqual(env.activeProvider, .gemini)
        env.saveAPIKey("gemini-key")
        env.selectedModelID = "models/gemini-2.5-flash"

        env.activeProvider = .groq
        XCTAssertFalse(env.hasAPIKey, "the Groq slot is empty even though Gemini has a key")
        XCTAssertNil(env.apiKey)
        XCTAssertNil(env.selectedModelID)
        env.saveAPIKey("groq-key")
        env.selectedModelID = "llama-3.3-70b-versatile"
        XCTAssertEqual(env.apiKey, "groq-key")

        env.activeProvider = .gemini
        XCTAssertEqual(env.apiKey, "gemini-key")
        XCTAssertEqual(env.selectedModelID, "models/gemini-2.5-flash")
        XCTAssertEqual(env.apiKey(for: .groq), "groq-key")
        env.removeAPIKey()
        XCTAssertNil(env.apiKey(for: .gemini))
        XCTAssertEqual(env.apiKey(for: .groq), "groq-key", "removing one provider's key leaves the others")
    }

    func testProviderChoiceSurvivesARestart() {
        let first = makeEnvironment()
        first.activeProvider = .openRouter
        first.selectedModelID = "openai/gpt-4o-mini"
        let second = makeEnvironment()
        XCTAssertEqual(second.activeProvider, .openRouter)
        XCTAssertEqual(second.selectedModelID, "openai/gpt-4o-mini")
    }

    func testBackupKeyBelongsToTheActiveProvider() {
        let env = makeEnvironment()
        env.activeProvider = .groq
        env.saveAPIKey("main")
        XCTAssertTrue(env.saveFallbackKey("backup"))
        XCTAssertTrue(env.hasFallbackKey)
        env.activeProvider = .gemini
        XCTAssertFalse(env.hasFallbackKey)
        XCTAssertNil(env.fallbackAPIKey)
    }

    func testPronunciationNeedsAGeminiKeyWhateverProviderIsActive() {
        let env = makeEnvironment()
        env.activeProvider = .groq
        env.saveAPIKey("groq-key")
        XCTAssertTrue(env.hasAPIKey)
        XCTAssertFalse(env.hasSpeechKey)
        XCTAssertNil(env.speechKey)
        env.activeProvider = .gemini
        env.saveAPIKey("gemini-key")
        env.activeProvider = .groq
        XCTAssertTrue(env.hasSpeechKey)
        XCTAssertEqual(env.speechKey, "gemini-key", "speech still uses the Gemini key while Groq answers the rest")
    }

    func testAModelThatCannotSeeSendsChatPhotosToTheOnDeviceReader() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.activeProvider = .groq
        let blind = AIModel(id: "llama-3.3-70b-versatile", displayName: "l", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .groq, acceptsImages: false)
        mock.listModelsResult = .success([blind])
        env.saveAPIKey("k")
        await env.catalogue.refresh(apiKey: "k", using: mock)
        env.selectedModelID = blind.id
        env.assistantSettings.photoReading = .model
        XCTAssertEqual(env.effectiveAssistantSettings.photoReading, .onDevice)
        XCTAssertEqual(env.assistantSettings.photoReading, .model, "the person's own setting is left alone")
    }

    func testUseProviderPicksAModelWhenTheKeyIsAlreadyThere() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        let llama = AIModel(id: "llama-3.3-70b-versatile", displayName: "l", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .groq)
        mock.listModelsResult = .success([llama])
        env.activeProvider = .groq
        env.saveAPIKey("k")
        env.activeProvider = .gemini
        await env.useProvider(.groq)
        XCTAssertEqual(env.activeProvider, .groq)
        XCTAssertEqual(env.selectedModelID, "llama-3.3-70b-versatile")
    }
}

final class OpenAICompatibleResilienceTests: XCTestCase {
    private let model = AIModel(id: "some/model", displayName: "m", description: nil, inputTokenLimit: nil, outputTokenLimit: nil, provider: .openRouter)

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testThinkingBlocksAreRemoved() {
        XCTAssertEqual(OpenAICompatibleClient.withoutThinking("<think>hmm {\"a\":0}</think>\n{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(OpenAICompatibleClient.withoutThinking("plain"), "plain")
        XCTAssertEqual(OpenAICompatibleClient.withoutThinking("<think>cut off"), "", "a reply cut inside its thinking has no answer")
    }

    func testTooLargeTokenLimitIsRetriedSmaller() async {
        let limits = Box<[Int]>([])
        MockURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            let limit = body?["max_tokens"] as? Int ?? 0
            limits.value.append(limit)
            if limit > 4096 {
                return (400, try! JSONSerialization.data(withJSONObject: ["error": ["message": "max_tokens is too large: 8192. This model supports at most 4096"]]))
            }
            return (200, try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "ok"], "finish_reason": "stop"]]]))
        }
        let client = OpenAICompatibleClient(provider: .openRouter, session: MockURLProtocol.session())
        let result = await client.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "k", model: model, temperature: 0)
        XCTAssertEqual(try? result.get(), "ok")
        XCTAssertEqual(limits.value, [8192, 4096])
    }

    func testWordGenerationAlsoFallsBackWhenJSONModeIsRefused() async {
        let modes = Box<[Bool]>([])
        MockURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            let json = body?["response_format"] != nil
            modes.value.append(json)
            if json { return (400, try! JSONSerialization.data(withJSONObject: ["error": ["message": "json mode is not supported"]])) }
            return (200, try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "not json"], "finish_reason": "stop"]]]))
        }
        let client = OpenAICompatibleClient(provider: .openRouter, session: MockURLProtocol.session())
        _ = await client.generateWord("hablar", apiKey: "k", model: model, language: .english)
        XCTAssertEqual(modes.value, [true, false])
    }
}
