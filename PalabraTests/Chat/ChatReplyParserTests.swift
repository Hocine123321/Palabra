import XCTest
@testable import Palabra

final class ChatReplyParserTests: XCTestCase {
    private func parsed(_ raw: String, file: StaticString = #filePath, line: UInt = #line) -> ChatReply? {
        guard case .success(let reply) = ChatReplyParser.parse(raw) else { XCTFail("expected success for \(raw)", file: file, line: line); return nil }
        return reply
    }

    func testPlainTextHasNoCalls() {
        let reply = parsed("  ¡Hola! How can I help?  ")
        XCTAssertEqual(reply?.say, "¡Hola! How can I help?")
        XCTAssertEqual(reply?.calls, [])
    }

    func testTextThenActions() {
        let reply = parsed("Let me look.\n---ACTIONS---\n[{\"capability\":\"library.words\",\"args\":{\"limit\":5}},{\"capability\":\"review.list\"}]")
        XCTAssertEqual(reply?.say, "Let me look.")
        XCTAssertEqual(reply?.calls.map(\.capability), ["library.words", "review.list"])
        XCTAssertEqual(reply?.calls.first?.args["limit"]?.intValue, 5)
        XCTAssertEqual(reply?.calls.last?.args, .object([:]))
    }

    func testCodeFenceAroundActionsIsStripped() {
        let reply = parsed("ok\n---ACTIONS---\n```json\n[{\"capability\":\"a\",\"args\":{}}]\n```")
        XCTAssertEqual(reply?.calls.map(\.capability), ["a"])
    }

    func testEmptyOrMissingBlockMeansNoCalls() {
        XCTAssertEqual(parsed("done\n---ACTIONS---")?.calls, [])
        XCTAssertEqual(parsed("done\n---ACTIONS---\n[]")?.calls, [])
    }

    func testExtraCallsAreDropped() {
        let calls = (0..<9).map { "{\"capability\":\"c\($0)\"}" }.joined(separator: ",")
        XCTAssertEqual(parsed("x\n---ACTIONS---\n[\(calls)]")?.calls.count, ChatLimits.maxCallsPerReply)
    }

    func testMalformedBlocksFail() {
        for raw in [
            "x\n---ACTIONS---\nnot json",
            "x\n---ACTIONS---\n{\"capability\":\"a\"}",
            "x\n---ACTIONS---\n[{\"args\":{}}]",
            "x\n---ACTIONS---\n[{\"capability\":\"a\",\"args\":[1]}]",
        ] {
            guard case .failure(.malformedActions) = ChatReplyParser.parse(raw) else { XCTFail("expected failure for \(raw)"); continue }
        }
    }

    func testTextOnlyDropsTheBlock() {
        XCTAssertEqual(ChatReplyParser.textOnly("Sure.\n---ACTIONS---\nbroken").say, "Sure.")
        XCTAssertEqual(ChatReplyParser.textOnly("No block").say, "No block")
    }
}
