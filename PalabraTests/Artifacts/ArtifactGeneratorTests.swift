import XCTest
@testable import Palabra

final class ArtifactGeneratorTests: XCTestCase {
    private let model = AIModel(id: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 8192)
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("library.word", .read),
        makeCapability("stats.wordsPerDay", .read),
        makeCapability("stats.wordsPerWeek", .read),
        makeCapability("storage.set", .local),
    ])

    private func reply(title: String = "Weekdays", requests: String = "[]", blocks: String = #"[{"type":"text","text":"Lunes"}]"#, end: Bool = true) -> String {
        #"{"kind":"spec","title":"\#(title)","requests":\#(requests)}"# + "\n---PAYLOAD---\n" + #"{"blocks":\#(blocks)}"# + "\n" + (end ? "---END---" : "")
    }

    private func makeGenerator(_ mock: MockAIClient) -> ArtifactGenerator {
        ArtifactGenerator(ai: mock, registry: registry)
    }

    func testCreateSendsRequestVerbatimWithManualAndNoSchema() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply())
        let result = await makeGenerator(mock).create(request: "  table of Spanish weekdays  ", apiKey: "k", model: model)
        guard case .success(let draft) = result else { return XCTFail("expected success") }
        XCTAssertEqual(draft.title, "Weekdays")
        XCTAssertEqual(draft.kind, .spec)
        XCTAssertEqual(draft.prompt, "table of Spanish weekdays")
        XCTAssertEqual(mock.generateJSONCalls.count, 1)
        let call = mock.generateJSONCalls[0]
        XCTAssertEqual(call.prompt, "table of Spanish weekdays")
        XCTAssertNil(call.schema)
        for name in ["library.words", "library.word", "stats.wordsPerDay", "stats.wordsPerWeek", "---PAYLOAD---", "---END---"] {
            XCTAssertTrue(call.systemInstruction.contains(name), "system instruction misses \(name)")
        }
        XCTAssertFalse(call.systemInstruction.contains("storage.set"))
    }

    func testCreatedPayloadIsValidSpecJSON() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply(requests: #"["library.words"]"#, blocks: #"[{"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{}}}]"#))
        let result = await makeGenerator(mock).create(request: "my words", apiKey: "k", model: model)
        guard case .success(let draft) = result else { return XCTFail("expected success") }
        XCTAssertEqual(draft.requests, ["library.words"])
        guard case .success = SpecValidator.decode(String(decoding: draft.payload, as: UTF8.self)) else {
            return XCTFail("stored payload must decode")
        }
    }

    func testTooShortRequestFailsWithoutCallingAI() async {
        let mock = MockAIClient()
        let result = await makeGenerator(mock).create(request: "  a ", apiKey: "k", model: model)
        guard case .failure(.ai(.validationFailed)) = result else { return XCTFail("expected validationFailed") }
        XCTAssertTrue(mock.generateJSONCalls.isEmpty)
    }

    func testMalformedThenValidRetriesOnceWithAddendum() async {
        let mock = MockAIClient()
        mock.generateJSONScript = [.success("not an envelope"), .success(reply())]
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        guard case .success = result else { return XCTFail("expected success after retry") }
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
        XCTAssertEqual(mock.generateJSONCalls[0].prompt, "weekdays")
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.hasPrefix("weekdays"))
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("NOT IN THE OUTPUT FORMAT"))
    }

    func testMalformedTwiceFailsAfterExactlyTwoCalls() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success("still nothing")
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        guard case .failure(.malformedEnvelope) = result else { return XCTFail("expected malformedEnvelope") }
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
    }

    func testMissingEndIsRetriedAsTruncated() async {
        let mock = MockAIClient()
        mock.generateJSONScript = [.success(reply(end: false)), .success(reply())]
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("CUT OFF"))
    }

    func testClientTruncatedErrorIsRetriedOnce() async {
        let mock = MockAIClient()
        mock.generateJSONScript = [.failure(.truncated), .success(reply())]
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("CUT OFF"))
    }

    func testTruncatedTwiceFails() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .failure(.truncated)
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.truncated))
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
    }

    func testOtherAIErrorsAreNotRetried() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .failure(.rateLimited)
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.ai(.rateLimited)))
        XCTAssertEqual(mock.generateJSONCalls.count, 1)
    }

    func testEmptySpecIsInvalidAndRetried() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply(blocks: "[]"))
        let result = await makeGenerator(mock).create(request: "weekdays", apiKey: "k", model: model)
        guard case .failure(.invalidSpec) = result else { return XCTFail("expected invalidSpec") }
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("COULD NOT BE USED"))
    }

    func testAppKindIsNotAvailableYet() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(#"{"kind":"app","title":"x"}"# + "\n---PAYLOAD---\n<html></html>\n---END---")
        let result = await makeGenerator(mock).create(request: "an app", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.kindNotAvailable))
        XCTAssertEqual(mock.generateJSONCalls.count, 1)
    }

    // MARK: update

    func testUpdateSendsCurrentPayloadAndKeepsTitle() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply(title: "Renamed by AI"))
        let current = Data(#"{"blocks":[{"type":"text","text":"old"}]}"#.utf8)
        let result = await makeGenerator(mock).update(kind: .spec, currentTitle: "Weekdays", currentPayload: current, change: "add Sunday", apiKey: "k", model: model)
        guard case .success(let draft) = result else { return XCTFail("expected success") }
        XCTAssertEqual(draft.title, "Weekdays")
        XCTAssertEqual(draft.prompt, "add Sunday")
        let prompt = mock.generateJSONCalls[0].prompt
        XCTAssertTrue(prompt.contains("add Sunday"))
        XCTAssertTrue(prompt.contains(ArtifactPrompts.currentPayloadHeader))
        XCTAssertTrue(prompt.contains(#"{"blocks":[{"type":"text","text":"old"}]}"#))
    }

    func testUpdateTruncatedAfterRetryIsTooLargeToExtend() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .failure(.truncated)
        let result = await makeGenerator(mock).update(kind: .spec, currentTitle: "T", currentPayload: Data("{}".utf8), change: "bigger", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.tooLargeToExtend))
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
    }

    func testUpdateOfAppKindIsNotAvailable() async {
        let mock = MockAIClient()
        let result = await makeGenerator(mock).update(kind: .app, currentTitle: "T", currentPayload: Data(), change: "change it", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.kindNotAvailable))
        XCTAssertTrue(mock.generateJSONCalls.isEmpty)
    }
}
