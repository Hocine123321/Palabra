import XCTest
@testable import Palabra

final class LessonAuthorTests: XCTestCase {
    private let model = AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    private let raw = "Colonial movement began in 1830 in Algeria. The treaty was signed in 1847."

    private func reply(title: String = "Colonial movement", text: String = "It began in 1830.", notes: String = "[]", extraPages: Int = 0) -> String {
        var pages = [#"{"title":"Start","blocks":[{"type":"paragraph","text":"\#(text)"}]}"#]
        for _ in 0..<extraPages { pages.append(#"{"title":"Extra","blocks":[{"type":"paragraph","text":"Algeria"}]}"#) }
        return #"{"title":"\#(title)","pages":[\#(pages.joined(separator: ","))],"transcriptionNotes":\#(notes)}"#
    }

    private func format(_ mock: MockAIClient, taken: Set<String> = []) async -> Result<LessonDraft, LessonAuthorError> {
        await LessonAuthor(ai: mock).format(rawText: raw, bookTitle: "History", language: "en", instruction: nil, takenLessonIDs: taken, apiKey: "k", model: model)
    }

    func testTranscribeSendsTheImageBytesAndAFaithfulTranscriptionPrompt() async throws {
        let mock = MockAIClient()
        mock.imageResult = .success(#"{"text":"line one\nline two","uncertain":["word at the end of line 2"]}"#)
        let photo = AIImage(data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let result = await LessonAuthor(ai: mock).transcribe(photo: photo, apiKey: "k", model: model, language: "ar")
        XCTAssertEqual(try result.get(), Transcription(text: "line one\nline two", uncertain: ["word at the end of line 2"]))
        let call = try XCTUnwrap(mock.imageCalls.first)
        XCTAssertEqual(call.image, photo)
        XCTAssertTrue(call.systemInstruction.contains("Do not correct"))
        XCTAssertTrue(call.systemInstruction.contains("[?]"))
        XCTAssertTrue(call.systemInstruction.contains("\"ar\""))
    }

    func testTranscribeOfEmptyTextIsNothingRead() async {
        let mock = MockAIClient()
        mock.imageResult = .success(#"{"text":"  ","uncertain":[]}"#)
        let result = await LessonAuthor(ai: mock).transcribe(photo: AIImage(data: Data([1]), mimeType: "image/jpeg"), apiKey: "k", model: model, language: "ar")
        XCTAssertEqual(result.failureValue, .nothingRead)
    }

    func testFormatPromptHasTheRawTextAndTheSystemTextHasTheRules() async throws {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply())
        _ = await format(mock)
        let call = try XCTUnwrap(mock.generateJSONCalls.first)
        XCTAssertTrue(call.prompt.contains(raw))
        XCTAssertNil(call.schema)
        for block in ["heading", "paragraph", "list", "keyPoint", "quote", "timeline", "stats", "comparison", "causeEffect", "process", "definitions"] {
            XCTAssertTrue(call.systemInstruction.contains("\"\(block)\""), "system text misses \(block)")
        }
        XCTAssertTrue(call.systemInstruction.contains("Use only the source text"))
        XCTAssertTrue(call.systemInstruction.contains("transcriptionNotes"))
    }

    func testFormatDecodesValidatesAndAssignsIDs() async throws {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply(notes: #"["unclear word"]"#))
        let draft = try await format(mock).get()
        XCTAssertEqual(draft.lesson.id, "colonial-movement")
        XCTAssertEqual(draft.lesson.pages.map(\.id), ["p1"])
        XCTAssertEqual(draft.lesson.transcriptionNotes, ["unclear word"])
        XCTAssertTrue(draft.isClean)
        XCTAssertEqual(mock.generateJSONCalls.count, 1)
    }

    func testNewNumberTriggersOneRetryWithTheOffendingNumber() async throws {
        let mock = MockAIClient()
        mock.generateJSONScript = [.success(reply(text: "It began in 1954.")), .success(reply(text: "It began in 1830."))]
        let draft = try await format(mock).get()
        XCTAssertTrue(draft.isClean)
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("1954"))
    }

    func testStillFailingAfterTheRetryReturnsTheDraftWithTheBlockedNumbers() async throws {
        let mock = MockAIClient()
        mock.generateJSONResult = .success(reply(text: "It began in 1954."))
        let draft = try await format(mock).get()
        XCTAssertEqual(draft.report.blockedNumbers, ["1954"])
        XCTAssertFalse(draft.isClean)
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
    }

    func testAStructurallyInvalidLessonRetriesOnceWithTheValidatorProblems() async throws {
        let mock = MockAIClient()
        let empty = #"{"title":"T","pages":[{"title":"Start","blocks":[]}]}"#
        mock.generateJSONScript = [.success(empty), .success(reply())]
        let draft = try await format(mock).get()
        XCTAssertTrue(draft.isClean)
        XCTAssertTrue(mock.generateJSONCalls[1].prompt.contains("no blocks"))
    }

    func testIDsFromTheAppReplaceNothingTheAIWrote() async throws {
        let mock = MockAIClient()
        let withIDs = #"{"id":"a/b","title":"Colonial movement","pages":[{"id":"x/y","title":"A","blocks":[{"type":"paragraph","text":"Algeria"}]},{"id":"x/y","title":"B","blocks":[{"type":"paragraph","text":"Algeria"}]}]}"#
        mock.generateJSONResult = .success(withIDs)
        let draft = try await format(mock, taken: ["colonial-movement"]).get()
        XCTAssertEqual(draft.lesson.id, "colonial-movement-2")
        XCTAssertEqual(draft.lesson.pages.map(\.id), ["p1", "p2"])
    }

    func testReviseKeepsPageIDsByPositionAndGivesNewPagesFreshIDs() async throws {
        let mock = MockAIClient()
        let current = Lesson(id: "keep-me", version: 3, title: "T", pages: [
            LessonPage(id: "intro", title: "A", blocks: [.paragraph("Algeria")]),
            LessonPage(id: "p2", title: "B", blocks: [.paragraph("Algeria")]),
        ])
        mock.generateJSONResult = .success(reply(extraPages: 2)) // 3 pages come back
        let draft = try await LessonAuthor(ai: mock).revise(current: current, rawText: raw, instruction: "make page 2 a list", bookTitle: "History", language: "en", apiKey: "k", model: model).get()
        XCTAssertEqual(draft.lesson.id, "keep-me")
        XCTAssertEqual(draft.lesson.version, 4)
        XCTAssertEqual(draft.lesson.pages.map(\.id), ["intro", "p2", "p1"])
        let call = try XCTUnwrap(mock.generateJSONCalls.first)
        XCTAssertTrue(call.prompt.contains("make page 2 a list"))
        XCTAssertTrue(call.prompt.contains(raw))
        XCTAssertTrue(call.prompt.contains("\"id\" : \"intro\""))
    }

    func testMalformedJSONRetriesOnceThenIsAnError() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .success("this is not json")
        let result = await format(mock)
        guard case .failure(.malformed) = result else { return XCTFail("expected malformed, got \(result)") }
        XCTAssertEqual(mock.generateJSONCalls.count, 2)
    }

    func testABackendFailurePropagatesWithoutARetry() async {
        let mock = MockAIClient()
        mock.generateJSONResult = .failure(.offline)
        let result = await format(mock)
        XCTAssertEqual(result.failureValue, .ai(.offline))
        XCTAssertEqual(mock.generateJSONCalls.count, 1)
    }

    func testLessonIDSlugs() {
        XCTAssertEqual(LessonIDs.uniqueLessonID(from: "Colonial Movement!", taken: []), "colonial-movement")
        XCTAssertEqual(LessonIDs.uniqueLessonID(from: "الاستعمار", taken: []), "lesson")
        XCTAssertEqual(LessonIDs.uniqueLessonID(from: "الاستعمار", taken: ["lesson", "lesson-2"]), "lesson-3")
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}
