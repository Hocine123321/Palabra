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
        let result = await client.generateWord("hablar", apiKey: "key", model: model)
        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(calls.value, 2)
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
}
