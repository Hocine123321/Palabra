import XCTest
@testable import Palabra

final class CardGeneratorTests: XCTestCase {
    private let model = AIModel(id: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 8192)
    private let notes = "The mitochondria is the powerhouse of the cell. Ribosomes build proteins."

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func deckJSON(title: String = "Cell biology", cards: [(String, String)] = [("Powerhouse of the cell?", "Mitochondria"), ("What builds proteins?", "Ribosomes")]) -> String {
        let payload: [String: Any] = ["title": title, "cards": cards.map { ["front": $0.0, "back": $0.1] }]
        return String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    }

    private func geminiResponse(text: String) -> Data {
        let root: [String: Any] = ["candidates": [["content": ["parts": [["text": text]]]]]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func requestBody(_ request: URLRequest?) -> [String: Any]? {
        guard let data = request?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - What is actually sent

    func testRequestBodyContainsTheNotesTheInstructionAndTheSchema() async {
        let captured = Box<URLRequest?>(nil)
        let reply = geminiResponse(text: deckJSON())
        MockURLProtocol.handler = { request in
            captured.value = request
            return (200, reply)
        }
        let generator = CardGenerator(ai: GeminiClient(session: MockURLProtocol.session()))
        let result = await generator.generate(notes: "  \(notes)  ", apiKey: "key", model: model)

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        let body = requestBody(captured.value)
        let contents = body?["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, notes) // the real notes, trimmed, not a placeholder

        let system = body?["systemInstruction"] as? [String: Any]
        let systemText = (system?["parts"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertTrue(systemText?.contains("flashcards") == true)
        XCTAssertFalse(systemText?.contains("\\(") == true) // no un-interpolated placeholders
        XCTAssertTrue(systemText?.contains("\(CardGeneratorLimits.maxCards)") == true)

        let config = body?["generationConfig"] as? [String: Any]
        let schema = config?["responseSchema"] as? [String: Any]
        XCTAssertNotNil((schema?["properties"] as? [String: Any])?["cards"])
        XCTAssertEqual(config?["responseMimeType"] as? String, "application/json")
    }

    func testLongNotesAreTruncatedBeforeSending() async {
        let captured = Box<URLRequest?>(nil)
        let reply = geminiResponse(text: deckJSON())
        MockURLProtocol.handler = { request in
            captured.value = request
            return (200, reply)
        }
        let generator = CardGenerator(ai: GeminiClient(session: MockURLProtocol.session()))
        _ = await generator.generate(notes: String(repeating: "a", count: 20_000), apiKey: "key", model: model)
        let contents = requestBody(captured.value)?["contents"] as? [[String: Any]]
        let text = ((contents?.first?["parts"] as? [[String: Any]])?.first?["text"]) as? String
        XCTAssertEqual(text?.count, CardGeneratorLimits.maxNotesLength)
    }

    func testTooShortNotesNeverReachTheNetwork() async {
        let called = Box(false)
        MockURLProtocol.handler = { _ in
            called.value = true
            return (200, Data())
        }
        let generator = CardGenerator(ai: GeminiClient(session: MockURLProtocol.session()))
        let result = await generator.generate(notes: "short", apiKey: "key", model: model)
        guard case .failure = result else { return XCTFail("expected failure") }
        XCTAssertFalse(called.value)
    }

    // MARK: - Results

    func testSuccessReturnsDraftsAndTitle() async {
        let ai = MockAIClient()
        ai.generateJSONResult = .success(deckJSON())
        let result = await CardGenerator(ai: ai).generate(notes: notes, apiKey: "key", model: model)
        guard case .success(let deck) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(deck.title, "Cell biology")
        XCTAssertEqual(deck.cards.map(\.front), ["Powerhouse of the cell?", "What builds proteins?"])
        XCTAssertEqual(deck.cards.map(\.back), ["Mitochondria", "Ribosomes"])
    }

    func testClientErrorsPassThrough() async {
        let ai = MockAIClient()
        ai.generateJSONResult = .failure(.rateLimited)
        let result = await CardGenerator(ai: ai).generate(notes: notes, apiKey: "key", model: model)
        XCTAssertEqual(result, .failure(.rateLimited))
    }

    // MARK: - Validation

    func testParseRejectsGarbageAndEmptyOutput() {
        XCTAssertEqual(CardGenerator.parse("not json"), .failure(.malformedResponse))
        XCTAssertEqual(CardGenerator.parse("{}"), .failure(.malformedResponse))
        XCTAssertEqual(CardGenerator.parse(deckJSON(cards: [])), .failure(.malformedResponse))
        XCTAssertEqual(CardGenerator.parse(deckJSON(cards: [("  ", "x"), ("y", "")])), .failure(.malformedResponse))
    }

    func testParseTrimsDropsBlankAndDeduplicatesFronts() {
        let json = deckJSON(cards: [(" Q1 ", " A1 "), ("q1", "other"), ("", "x"), ("Q2", "A2")])
        guard case .success(let deck) = CardGenerator.parse(json) else { return XCTFail("expected success") }
        XCTAssertEqual(deck.cards.map(\.front), ["Q1", "Q2"])
        XCTAssertEqual(deck.cards.map(\.back), ["A1", "A2"])
    }

    func testParseCapsCountAndFieldLengths() {
        let many = (0..<100).map { ("front \($0)", String(repeating: "b", count: 1000)) }
        guard case .success(let deck) = CardGenerator.parse(deckJSON(title: String(repeating: "t", count: 500), cards: many)) else { return XCTFail("expected success") }
        XCTAssertEqual(deck.cards.count, CardGeneratorLimits.maxCards)
        XCTAssertTrue(deck.cards.allSatisfy { $0.back.count == CardGeneratorLimits.maxFieldLength })
        XCTAssertEqual(deck.title.count, CardGeneratorLimits.maxTitleLength)
    }

    func testDraftsGetDistinctIdentitiesEvenWithIdenticalText() {
        // Two different cards can share a back; identity must never come from AI text.
        guard case .success(let deck) = CardGenerator.parse(deckJSON(cards: [("a", "same"), ("b", "same")])) else { return XCTFail("expected success") }
        XCTAssertEqual(Set(deck.cards.map(\.id)).count, 2)
    }
}
