import XCTest
@testable import Palabra

final class GeminiClientTests: XCTestCase {
    private var client: GeminiClient!
    private let model = AIModel(id: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 8192)

    override func setUp() {
        super.setUp()
        client = GeminiClient(session: MockURLProtocol.session())
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func sampleContent() -> WordContent {
        WordContent(
            word: "hablar",
            examples: [
                .init(context: "At school", spanish: "Hablo español en clase.", english: "I speak Spanish in class."),
                .init(context: "With friends", spanish: "¿Puedes hablar más despacio?", english: "Can you speak more slowly?"),
                .init(context: "On the phone", spanish: "Necesito hablar con el médico.", english: "I need to speak with the doctor.")
            ],
            meaning: .init(translations: ["to speak", "to talk"], explanation: "Used for speaking or talking."),
            usage: .init(explanation: "A regular -ar verb.", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: "hablo", note: nil)])]),
            similarWords: [.init(word: "conversar", difference: "More formal, implies a two-way conversation.")]
        )
    }

    private func sampleContentJSON() -> String {
        let data = try! JSONEncoder().encode(sampleContent())
        return String(data: data, encoding: .utf8)!
    }

    private func responseJSON(parts: [[String: Any]], finishReason: String? = nil, blockReason: String? = nil) -> Data {
        var candidate: [String: Any] = ["content": ["parts": parts]]
        if let finishReason { candidate["finishReason"] = finishReason }
        var root: [String: Any] = ["candidates": [candidate]]
        if let blockReason { root["promptFeedback"] = ["blockReason": blockReason] }
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func errorJSON(message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": ["code": 400, "message": message, "status": "ERROR"]])
    }

    // MARK: - generateWord: success paths

    func testGenerateWordSuccessParsesAndValidates() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": sampleContentJSON()]])) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        guard case .success(let content) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(content.word, "hablar")
    }

    func testGenerateWordStripsCodeFences() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": "```json\n\(sampleContentJSON())\n```"]])) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        guard case .success = result else { return XCTFail("expected success, got \(result)") }
    }

    func testGenerateWordJoinsPartsInOrderAndSkipsThoughtParts() async {
        let json = sampleContentJSON()
        let mid = json.index(json.startIndex, offsetBy: json.count / 2)
        let first = String(json[..<mid])
        let second = String(json[mid...])
        MockURLProtocol.handler = { [self] _ in
            (200, responseJSON(parts: [
                ["text": "thinking about it...", "thought": true],
                ["text": first],
                ["text": second]
            ]))
        }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        guard case .success(let content) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(content.word, "hablar")
    }

    // MARK: - generateWord: error mapping

    func testGenerateWordMapsInvalidAPIKey() async {
        MockURLProtocol.handler = { [self] _ in (400, errorJSON(message: "API key not valid. Please pass a valid API key.")) }
        let result = await client.generateWord("hablar", apiKey: "bad", model: model)
        XCTAssertEqual(result, .failure(.invalidAPIKey))
    }

    func testGenerateWordMapsPermissionDenied() async {
        MockURLProtocol.handler = { _ in (403, Data()) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.permissionDenied))
    }

    func testGenerateWordMapsRateLimited() async {
        MockURLProtocol.handler = { _ in (429, Data()) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.rateLimited))
    }

    func testGenerateWordMapsServerError() async {
        MockURLProtocol.handler = { _ in (503, Data()) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.serverError(503)))
    }

    func testGenerateWordMapsOffline() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.offline))
    }

    func testGenerateWordMapsTimeout() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.timeout))
    }

    func testGenerateWordMapsCancelled() async {
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.cancelled))
    }

    func testGenerateJSONUnwrapsAFenceThatFollowsChatter() async {
        let reply = "Here is the JSON you asked for:\n```json\n{\"a\": 1}\n```\nHope that helps."
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": reply]])) }
        let result = await client.generateJSON(prompt: "x", systemInstruction: "y", schema: nil, apiKey: "key", model: model, temperature: 0)
        XCTAssertEqual(result, .success("{\"a\": 1}"))
    }

    func testGenerateJSONLeavesJSONWithBackticksInsideAStringAlone() async {
        let reply = "{\"note\": \"use ```code``` here\"}"
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": reply]])) }
        let result = await client.generateJSON(prompt: "x", systemInstruction: "y", schema: nil, apiKey: "key", model: model, temperature: 0)
        XCTAssertEqual(result, .success(reply))
    }

    func testAbsurdlyLargeReplyIsRefused() async {
        MockURLProtocol.handler = { _ in (200, Data(count: GeminiClient.maxResponseBytes + 1)) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.malformedResponse))
    }

    func testGenerateWordMapsBlocked() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": ""]], blockReason: "SAFETY")) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.blocked("SAFETY")))
    }

    func testGenerateWordMapsTruncated() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": ""]], finishReason: "MAX_TOKENS")) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.truncated))
    }

    func testGenerateWordValidationFailurePassesThrough() async {
        // Structurally complete (decodes fine) but empty, so ContentValidator — not the
        // decoder — is what rejects it.
        let incomplete = WordContent(
            word: "hablar",
            examples: [],
            meaning: .init(translations: [], explanation: ""),
            usage: .init(explanation: "", register: "", nuance: nil),
            forms: .init(partOfSpeech: "", groups: []),
            similarWords: []
        )
        let text = String(data: try! JSONEncoder().encode(incomplete), encoding: .utf8)!
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": text]])) }
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        guard case .failure(.validationFailed) = result else { return XCTFail("expected validationFailed, got \(result)") }
    }

    func testGenerateWordFallsBackWhenSchemaUnsupported() async {
        let calls = Box(0)
        MockURLProtocol.handler = { [self] _ in
            calls.value += 1
            if calls.value == 1 {
                return (400, errorJSON(message: "Invalid JSON payload received. Unknown name \"response_schema\"."))
            }
            return (200, responseJSON(parts: [["text": sampleContentJSON()]]))
        }
        let result = await client.generateWord("hablar", apiKey: "key", model: model, language: .arabic)
        guard case .success(let content) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(calls.value, 2)
        // The fallback (no-schema) path must thread `language` through too, not just the
        // happy path — this is exactly what a missing argument at the call site would break.
        XCTAssertEqual(content.contentLanguage, .arabic)
    }

    // MARK: - listModels

    func testListModelsFollowsPaginationAndDropsNonGenerateContent() async {
        MockURLProtocol.handler = { request in
            let hasToken = request.url?.query?.contains("pageToken=page2") ?? false
            if hasToken {
                let json: [String: Any] = ["models": [
                    ["name": "models/gemini-2.5-pro", "displayName": "Gemini 2.5 Pro", "supportedGenerationMethods": ["generateContent"]]
                ]]
                return (200, try! JSONSerialization.data(withJSONObject: json))
            }
            let json: [String: Any] = [
                "models": [
                    ["name": "models/gemini-2.5-flash", "displayName": "Gemini 2.5 Flash", "supportedGenerationMethods": ["generateContent"]],
                    ["name": "models/embedding-001", "displayName": "Embedding", "supportedGenerationMethods": ["embedContent"]]
                ],
                "nextPageToken": "page2"
            ]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let result = await client.listModels(apiKey: "key")
        guard case .success(let models) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(Set(models.map(\.id)), ["models/gemini-2.5-flash", "models/gemini-2.5-pro"])
    }

    func testListModelsStopsWhenTheServerRepeatsAPageToken() async {
        let calls = Box(0)
        MockURLProtocol.handler = { _ in
            calls.value += 1
            let json: [String: Any] = [
                "models": [["name": "models/gemini-2.5-flash", "displayName": "Gemini 2.5 Flash", "supportedGenerationMethods": ["generateContent"]]],
                "nextPageToken": "same"
            ]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let result = await client.listModels(apiKey: "key")
        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertLessThanOrEqual(calls.value, 3, "a repeated token must not loop")
    }

    func testAnUnencodableRequestFailsInsteadOfSendingAnEmptyBody() async {
        let sent = Box(false)
        MockURLProtocol.handler = { _ in sent.value = true; return (200, Data()) }
        let result = await client.generateJSON(prompt: "x", systemInstruction: "y", schema: ["bad": Double.nan], apiKey: "key", model: model, temperature: 0)
        guard case .failure = result else { return XCTFail("expected a failure, got \(result)") }
        XCTAssertFalse(sent.value, "nothing may be sent when the body cannot be built")
    }

    // MARK: - sendChat

    func testSendChatReturnsAssistantText() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": "¡Claro! Aquí tienes otro ejemplo."]])) }
        let result = await client.sendChat(apiKey: "key", model: model, word: sampleContent(), history: [], newMessage: "another example please")
        XCTAssertEqual(result, .success("¡Claro! Aquí tienes otro ejemplo."))
    }

    func testSendChatEmptyTextIsMalformed() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": ""]], finishReason: "STOP")) }
        let result = await client.sendChat(apiKey: "key", model: model, word: sampleContent(), history: [], newMessage: "hi")
        XCTAssertEqual(result, .failure(.malformedResponse))
    }

    // MARK: - Language-aware prompts
    //
    // Regression coverage for a prior bug where the system-instruction template
    // used unescaped "(name)" placeholders instead of Swift's "\(name)"
    // interpolation, so the learner's language and the chat's word context
    // were never actually sent to the model.

    private func capturedSystemInstruction(from request: URLRequest?) -> String? {
        guard let data = request?.httpBody,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instruction = body["systemInstruction"] as? [String: Any],
              let parts = instruction["parts"] as? [[String: Any]] else { return nil }
        return parts.first?["text"] as? String
    }

    func testGenerateWordSendsArabicLanguageInstruction() async {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { [self] request in
            captured.value = request
            return (200, responseJSON(parts: [["text": sampleContentJSON()]]))
        }
        _ = await client.generateWord("hablar", apiKey: "key", model: model, language: .arabic)
        let instruction = capturedSystemInstruction(from: captured.value)
        XCTAssertEqual(instruction?.contains("explanation language is Arabic"), true)
        XCTAssertEqual(instruction?.contains("Write every learner-facing explanation"), true)
        XCTAssertEqual(instruction?.contains("(learnerInstruction)"), false)
        XCTAssertEqual(instruction?.contains("(language.instructionName)"), false)
    }

    func testGenerateWordSendsEnglishLanguageInstructionByDefault() async {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { [self] request in
            captured.value = request
            return (200, responseJSON(parts: [["text": sampleContentJSON()]]))
        }
        _ = await client.generateWord("hablar", apiKey: "key", model: model, language: .english)
        let instruction = capturedSystemInstruction(from: captured.value)
        XCTAssertEqual(instruction?.contains("explanation language is English"), true)
    }

    func testSendChatIncludesWordContextJSON() async {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { [self] request in
            captured.value = request
            return (200, responseJSON(parts: [["text": "reply"]]))
        }
        _ = await client.sendChat(apiKey: "key", model: model, word: sampleContent(), history: [], newMessage: "hi", language: .arabic)
        let instruction = capturedSystemInstruction(from: captured.value)
        XCTAssertEqual(instruction?.contains("hablar"), true)
        XCTAssertEqual(instruction?.contains("Reply in Arabic"), true)
        XCTAssertEqual(instruction?.contains("(encoded)"), false)
        XCTAssertEqual(instruction?.contains("(replyLanguage)"), false)
    }

    // MARK: - synthesizeSpeech

    private let ttsModel = AIModel(id: "models/gemini-2.5-flash-tts", displayName: "Gemini 2.5 Flash TTS", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)

    private func requestBody(from request: URLRequest?) -> [String: Any]? {
        guard let data = request?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testGenerateJSONWithAPhotoSendsThePictureThenTheInstruction() async throws {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.handler = { [self] request in
            captured.value = request
            return (200, responseJSON(parts: [["text": #"{"found":true,"text":"x"}"#]]))
        }
        let image = AIImage(data: Data([1, 2, 3, 4]), mimeType: "image/jpeg")
        let result = await client.generateJSON(prompt: "Copy it.", image: image, systemInstruction: "sys", schema: ["type": "OBJECT"], apiKey: "key", model: model, temperature: 0)
        guard case .success = result else { return XCTFail("expected success, got \(result)") }

        let body = try XCTUnwrap(requestBody(from: captured.value))
        let contents = body["contents"] as? [[String: Any]]
        let parts = try XCTUnwrap(contents?.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        let inline = parts.first?["inlineData"] as? [String: Any]
        XCTAssertEqual(inline?["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(inline?["data"] as? String, Data([1, 2, 3, 4]).base64EncodedString(), "the picture bytes are really in the request")
        XCTAssertEqual(parts.last?["text"] as? String, "Copy it.")
        let config = body["generationConfig"] as? [String: Any]
        XCTAssertEqual(config?["responseMimeType"] as? String, "application/json")
    }

    func testSynthesizeSpeechSendsExpectedRequestShape() async {
        let captured = Box<URLRequest?>(nil)
        let wav = WAVAudio.wav(fromPCM: Data([1, 2, 3]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        MockURLProtocol.handler = { [self] request in
            captured.value = request
            return (200, responseJSON(parts: [["inlineData": ["mimeType": "audio/wav", "data": wav.base64EncodedString()]]]))
        }
        _ = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)

        XCTAssertEqual(captured.value?.url?.absoluteString.contains("models/gemini-2.5-flash-tts:generateContent"), true)
        let body = requestBody(from: captured.value)
        let contents = body?["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "hablar")

        let generationConfig = body?["generationConfig"] as? [String: Any]
        XCTAssertEqual(generationConfig?["responseModalities"] as? [String], ["AUDIO"])
        let speechConfig = generationConfig?["speechConfig"] as? [String: Any]
        let voiceConfig = speechConfig?["voiceConfig"] as? [String: Any]
        let prebuilt = voiceConfig?["prebuiltVoiceConfig"] as? [String: Any]
        XCTAssertEqual(prebuilt?["voiceName"] as? String, "Kore")
    }

    func testSynthesizeSpeechPassesThroughCompleteWAV() async {
        let wav = WAVAudio.wav(fromPCM: Data([10, 20, 30, 40]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        MockURLProtocol.handler = { [self] _ in
            (200, responseJSON(parts: [["inlineData": ["mimeType": "audio/wav", "data": wav.base64EncodedString()]]]))
        }
        let result = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)
        guard case .success(let data) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(data, wav)
    }

    func testSynthesizeSpeechWrapsHeaderlessPCM() async {
        let pcm = Data(repeating: 0x42, count: 200)
        MockURLProtocol.handler = { [self] _ in
            (200, responseJSON(parts: [["inlineData": ["mimeType": "audio/L16;codec=pcm;rate=24000", "data": pcm.base64EncodedString()]]]))
        }
        let result = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)
        guard case .success(let data) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(data.count, 44 + pcm.count)
        XCTAssertEqual(Array(data.prefix(4)), Array("RIFF".utf8))
    }

    func testSynthesizeSpeechFailsWhenNoInlineAudio() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": "no audio here"]])) }
        let result = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)
        XCTAssertEqual(result, .failure(.malformedResponse))
    }

    func testSynthesizeSpeechPropagatesBlockedReason() async {
        MockURLProtocol.handler = { [self] _ in (200, responseJSON(parts: [["text": "x"]], blockReason: "SAFETY")) }
        let result = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)
        XCTAssertEqual(result, .failure(.blocked("SAFETY")))
    }

    func testSynthesizeSpeechMapsHTTPErrorsLikeOtherEndpoints() async {
        MockURLProtocol.handler = { _ in (429, Data()) }
        let result = await client.synthesizeSpeech("hablar", apiKey: "key", model: ttsModel)
        XCTAssertEqual(result, .failure(.rateLimited))
    }
}
