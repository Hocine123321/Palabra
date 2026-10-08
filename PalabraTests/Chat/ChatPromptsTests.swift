import XCTest
@testable import Palabra

final class ChatPromptsTests: XCTestCase {
    func testSystemInstructionCarriesManualLanguageAndProtocol() {
        let text = ChatPrompts.systemInstruction(manual: "- library.words (read): lists words", language: .arabic, linkedWord: nil)
        XCTAssertTrue(text.contains("- library.words (read): lists words"))
        XCTAssertTrue(text.contains("Arabic"))
        XCTAssertTrue(text.contains(ChatReplyParser.marker))
        XCTAssertFalse(text.contains("---PAYLOAD---"))
        XCTAssertFalse(text.contains("opened this chat from the word"))
    }

    func testLinkedWordIsNamedWithItsId() {
        let id = UUID()
        let text = ChatPrompts.systemInstruction(manual: "", language: .english, linkedWord: (id, "hablar"))
        XCTAssertTrue(text.contains("\"hablar\""))
        XCTAssertTrue(text.contains(id.uuidString))
    }

    func testTranscriptRendersTurnsAndEveryActionState() {
        let actions = [
            ChatAction(capability: "library.words", argsJSON: "{\"limit\":5}", summary: "", isWrite: false, state: .applied, result: "[]"),
            ChatAction(capability: "words.add", argsJSON: "{}", summary: "", isWrite: true, state: .declined),
            ChatAction(capability: "review.flag", argsJSON: "{}", summary: "", isWrite: true, state: .failed, result: "bad arguments: x"),
            ChatAction(capability: "study.addCards", argsJSON: "{}", summary: "", isWrite: true, state: .pending),
        ]
        let turns = [
            ChatTurn(role: .user, text: "hello"),
            ChatTurn(role: .assistant, text: "working", actions: actions),
            ChatTurn(role: .assistant, text: "", status: .failed, errorText: "x"),
        ]
        let transcript = ChatPrompts.transcript(turns: turns)
        XCTAssertTrue(transcript.hasPrefix("CONVERSATION:\nUSER: hello\nASSISTANT: working"))
        XCTAssertTrue(transcript.contains("  [read library.words {\"limit\":5}] -> applied: []"))
        XCTAssertTrue(transcript.contains("-> declined by the user"))
        XCTAssertTrue(transcript.contains("-> failed: bad arguments: x"))
        XCTAssertTrue(transcript.contains("-> waiting for the user's approval"))
        XCTAssertTrue(transcript.hasSuffix("Write the next ASSISTANT reply now."))
        XCTAssertEqual(transcript.components(separatedBy: "ASSISTANT:").count - 1, 1) // the failed turn is skipped
    }

    func testTranscriptKeepsNewestTurnsWithinBudget() {
        let turns = (0..<10).map { ChatTurn(role: .user, text: "message \($0) " + String(repeating: "x", count: 100)) }
        let transcript = ChatPrompts.transcript(turns: turns, budget: 350)
        XCTAssertTrue(transcript.contains("message 9"))
        XCTAssertFalse(transcript.contains("message 0"))
    }
}
