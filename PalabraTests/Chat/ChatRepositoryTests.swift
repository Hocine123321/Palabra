import XCTest
@testable import Palabra

@MainActor
final class ChatRepositoryTests: XCTestCase {
    private var repo: SwiftDataChatRepository!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() { repo = SwiftDataChatRepository.inMemory() }

    func testCreateAndFind() {
        let word = UUID()
        let made = repo.create(title: "  hablar  ", wordID: word, turns: [ChatTurn(role: .user, text: "hi")], now: t0)
        XCTAssertEqual(made.title, "hablar")
        XCTAssertEqual(repo.conversation(id: made.id)?.turns.first?.text, "hi")
        XCTAssertEqual(repo.conversation(forWordID: word)?.id, made.id)
        XCTAssertNil(repo.conversation(forWordID: UUID()))
    }

    func testBlankTitleFallsBackAndLongTitleIsCapped() {
        XCTAssertEqual(repo.create(title: "   ", wordID: nil, turns: [], now: t0).title, ChatConversation.defaultTitle)
        XCTAssertEqual(repo.create(title: String(repeating: "x", count: 100), wordID: nil, turns: [], now: t0).title.count, ChatLimits.maxTitleLength)
    }

    func testConversationsAreNewestFirstAndSaveTouchesUpdatedAt() {
        let a = repo.create(title: "a", wordID: nil, turns: [], now: t0)
        let b = repo.create(title: "b", wordID: nil, turns: [], now: t0.addingTimeInterval(10))
        XCTAssertEqual(repo.conversations().map(\.title), ["b", "a"])
        repo.save(id: a.id, turns: [ChatTurn(role: .user, text: "x")], title: nil, now: t0.addingTimeInterval(20))
        XCTAssertEqual(repo.conversations().map(\.title), ["a", "b"])
        _ = b
    }

    func testSaveTrimsTurnsAndCapsTexts() {
        let c = repo.create(title: "t", wordID: nil, turns: [], now: t0)
        let turns = (0..<(ChatLimits.maxTurns + 5)).map { ChatTurn(role: .user, text: "m\($0)") }
        repo.save(id: c.id, turns: turns, title: nil, now: t0)
        let stored = repo.conversation(id: c.id)?.turns ?? []
        XCTAssertEqual(stored.count, ChatLimits.maxTurns)
        XCTAssertEqual(stored.first?.text, "m5")

        let action = ChatAction(capability: "x", argsJSON: "{}", summary: "s", isWrite: false, state: .applied, result: String(repeating: "r", count: 9_000))
        repo.save(id: c.id, turns: [ChatTurn(role: .assistant, text: String(repeating: "t", count: 20_000), actions: [action])], title: nil, now: t0)
        let capped = repo.conversation(id: c.id)?.turns.first
        XCTAssertEqual(capped?.text.count, ChatLimits.maxTextLength)
        XCTAssertEqual(capped?.actions.first?.result?.count, ChatLimits.maxResultLength)
    }

    func testDelete() {
        let c = repo.create(title: "t", wordID: nil, turns: [], now: t0)
        repo.delete(id: c.id)
        XCTAssertNil(repo.conversation(id: c.id))
    }

    func testTurnDecodingToleratesMissingFields() throws {
        let data = Data(#"[{"role":"user","text":"hi"}]"#.utf8)
        let turns = try JSONDecoder().decode([ChatTurn].self, from: data)
        XCTAssertEqual(turns.first?.text, "hi")
        XCTAssertEqual(turns.first?.status, .sent)
        XCTAssertEqual(turns.first?.actions, [])
    }
}
