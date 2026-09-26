import XCTest
@testable import Palabra

final class ChatHistoryBuilderTests: XCTestCase {
    private func msg(_ role: ChatMessage.Role, _ text: String, status: ChatMessage.Status = .sent) -> ChatMessage {
        ChatMessage(role: role, text: text, status: status)
    }

    func testExcludesFailedMessages() {
        let history = [msg(.user, "hola"), msg(.assistant, "fail", status: .failed), msg(.assistant, "¡hola!")]
        let turns = ChatHistoryBuilder.build(from: history)
        XCTAssertEqual(turns, [.init(role: .user, text: "hola"), .init(role: .assistant, text: "¡hola!")])
    }

    func testCapsAtLimitKeepingMostRecent() {
        let history = (0..<25).map { i in msg(i.isMultiple(of: 2) ? .user : .assistant, "m\(i)") }
        let turns = ChatHistoryBuilder.build(from: history, limit: 20)
        XCTAssertEqual(turns.count, 20)
        XCTAssertEqual(turns.first?.text, "m5")
        XCTAssertEqual(turns.last?.text, "m24")
    }

    func testMergesConsecutiveSameRole() {
        let history = [msg(.user, "one"), msg(.user, "two"), msg(.assistant, "reply")]
        let turns = ChatHistoryBuilder.build(from: history)
        XCTAssertEqual(turns, [.init(role: .user, text: "one\n\ntwo"), .init(role: .assistant, text: "reply")])
    }
}
