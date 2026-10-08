import XCTest
@testable import Palabra

/// Scripted model: returns queued replies in order and records every prompt and system instruction.
@MainActor
private final class Script {
    var replies: [Result<String, AIError>]
    private(set) var prompts: [String] = []
    private(set) var systems: [String] = []
    init(_ replies: [Result<String, AIError>]) { self.replies = replies }
    func next(prompt: String, system: String) -> Result<String, AIError> {
        prompts.append(prompt)
        systems.append(system)
        return replies.isEmpty ? .success("(script empty)") : replies.removeFirst()
    }
}

@MainActor
final class ChatSessionTests: XCTestCase {
    private var repository: SwiftDataChatRepository!
    private var readBox: CallBox!
    private var writeBox: CallBox!
    private var registry: CapabilityRegistry!

    override func setUp() {
        repository = SwiftDataChatRepository.inMemory()
        readBox = CallBox()
        writeBox = CallBox()
        registry = CapabilityRegistry([
            makeCapability("library.words", .read, box: readBox, result: .array([.string("hola")])),
            makeCapability("words.add", .write, box: writeBox, result: .object(["queued": .number(2)])),
            makeCapability("storage.get", .local),
            makeCapability("ai.generate", .ai),
        ])
    }

    private func makeSession(_ script: Script, wordID: UUID? = nil, title: String = ChatConversation.defaultTitle) -> ChatSession {
        let conversation = repository.create(title: title, wordID: wordID, turns: [], now: Date(timeIntervalSince1970: 0))
        return ChatSession(
            conversation: conversation,
            repository: repository,
            registry: registry,
            language: { .english },
            generate: { prompt, system in script.next(prompt: prompt, system: system) }
        )
    }

    private func reply(_ text: String, calls: String? = nil) -> Result<String, AIError> {
        .success(calls.map { "\(text)\n---ACTIONS---\n\($0)" } ?? text)
    }

    private let readCall = #"[{"capability":"library.words","args":{"limit":5}}]"#
    private let writeCall = #"[{"capability":"words.add","args":{"words":["a","b"]}}]"#

    func testPlainReplyIsSavedAndTitlesTheChat() async {
        let script = Script([reply("Hola!")])
        let session = makeSession(script)
        await session.send("  how are   you  ")
        XCTAssertEqual(session.turns.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.turns.last?.text, "Hola!")
        XCTAssertEqual(session.title, "how are you")
        XCTAssertEqual(session.phase, .idle)
        let stored = repository.conversation(id: session.conversationID)
        XCTAssertEqual(stored?.turns.count, 2)
        XCTAssertEqual(stored?.title, "how are you")
        XCTAssertTrue(script.prompts[0].contains("USER: how are   you"))
    }

    func testReadsRunAtOnceAndTheModelSeesTheResult() async {
        let script = Script([reply("Let me look.", calls: readCall), reply("You have hola.")])
        let session = makeSession(script)
        await session.send("what words do I have?")
        XCTAssertTrue(readBox.called)
        XCTAssertEqual(script.prompts.count, 2)
        XCTAssertTrue(script.prompts[1].contains("[read library.words {\"limit\":5}] -> applied: [\"hola\"]"))
        XCTAssertEqual(session.turns.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(session.turns[1].actions.first?.state, .applied)
        XCTAssertEqual(session.turns.last?.text, "You have hola.")
        XCTAssertFalse(session.hasPending)
    }

    func testWritesWaitThenRunOnApproval() async {
        let script = Script([reply("I'll add two words.", calls: writeCall), reply("Done, both queued.")])
        let session = makeSession(script)
        await session.send("add words")
        XCTAssertTrue(session.hasPending)
        XCTAssertFalse(writeBox.called)
        XCTAssertEqual(script.prompts.count, 1)
        XCTAssertEqual(session.turns.last?.actions.first?.state, .pending)

        await session.approvePending()
        XCTAssertTrue(writeBox.called)
        XCTAssertEqual(script.prompts.count, 2)
        XCTAssertTrue(script.prompts[1].contains("-> applied: {\"queued\":2}"))
        XCTAssertEqual(session.turns[1].actions.first?.state, .applied)
        XCTAssertEqual(session.turns.last?.text, "Done, both queued.")
        XCTAssertFalse(session.hasPending)
    }

    func testDecliningNeverRunsTheWriteAndTellsTheModel() async {
        let script = Script([reply("Adding.", calls: writeCall), reply("Okay, nothing changed.")])
        let session = makeSession(script)
        await session.send("add words")
        await session.declinePending()
        XCTAssertFalse(writeBox.called)
        XCTAssertEqual(session.turns[1].actions.first?.state, .declined)
        XCTAssertTrue(script.prompts[1].contains("-> declined by the user"))
        XCTAssertEqual(session.turns.last?.text, "Okay, nothing changed.")
    }

    func testTypingInsteadOfApprovingDeclinesThePendingWrite() async {
        let script = Script([reply("Adding.", calls: writeCall), reply("Sure, something else.")])
        let session = makeSession(script)
        await session.send("add words")
        await session.send("actually, never mind")
        XCTAssertFalse(writeBox.called)
        XCTAssertEqual(session.turns[1].actions.first?.state, .declined)
        XCTAssertFalse(session.hasPending)
    }

    func testUnknownAndNonChatCapabilitiesFailWithoutRunning() async {
        let calls = #"[{"capability":"nope","args":{}},{"capability":"storage.get","args":{}},{"capability":"ai.generate","args":{}}]"#
        let script = Script([reply("Trying.", calls: calls), reply("That did not work.")])
        let session = makeSession(script)
        await session.send("do things")
        XCTAssertEqual(session.turns[1].actions.map(\.state), [.failed, .failed, .failed])
        XCTAssertTrue(script.prompts[1].contains("-> failed: unknown capability"))
        XCTAssertEqual(session.turns.last?.text, "That did not work.")
    }

    func testModelFailureAppendsAFailedTurnAndRetryContinues() async {
        let script = Script([.failure(.rateLimited), reply("Back again.")])
        let session = makeSession(script)
        await session.send("hello")
        XCTAssertEqual(session.turns.last?.status, .failed)
        XCTAssertEqual(session.turns.last?.errorText, AIError.rateLimited.userMessage)
        await session.retry()
        XCTAssertEqual(session.turns.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.turns.last?.text, "Back again.")
        XCTAssertEqual(session.turns.last?.status, .sent)
    }

    func testMalformedActionsRetryOnceWithTheProblemThenSucceed() async {
        let script = Script([reply("Oops.", calls: "not json"), reply("Fixed.", calls: readCall), reply("Here you go.")])
        let session = makeSession(script)
        await session.send("list")
        XCTAssertTrue(script.prompts[1].contains("could not be used"))
        XCTAssertTrue(script.prompts[1].hasPrefix(script.prompts[0]))
        XCTAssertTrue(readBox.called)
        XCTAssertEqual(session.turns.last?.text, "Here you go.")
    }

    func testStillMalformedAfterTheRetryFallsBackToTheText() async {
        let script = Script([reply("First.", calls: "bad"), reply("Second.", calls: "still bad")])
        let session = makeSession(script)
        await session.send("list")
        XCTAssertEqual(script.prompts.count, 2)
        XCTAssertEqual(session.turns.last?.text, "Second.")
        XCTAssertEqual(session.turns.last?.actions.count, 0)
    }

    func testTheLoopStopsAfterTheRoundLimit() async {
        let script = Script(Array(repeating: reply("Again.", calls: readCall), count: 10))
        let session = makeSession(script)
        await session.send("loop")
        XCTAssertEqual(script.prompts.count, ChatLimits.maxRoundsPerMessage)
        XCTAssertEqual(session.phase, .idle)
    }

    func testEmptyReplyIsAFailure() async {
        let script = Script([.success("   ")])
        let session = makeSession(script)
        await session.send("hello")
        XCTAssertEqual(session.turns.last?.status, .failed)
    }

    func testClearEmptiesAndSaves() async {
        let script = Script([reply("Hi.")])
        let session = makeSession(script)
        await session.send("hello")
        session.clear()
        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertEqual(repository.conversation(id: session.conversationID)?.turns.count, 0)
    }

    func testLinkedWordReachesTheSystemInstructionAndKeepsItsTitle() async {
        let id = UUID()
        let script = Script([reply("Sure.")])
        let session = makeSession(script, wordID: id, title: "hablar")
        await session.send("explain it")
        XCTAssertTrue(script.systems[0].contains(id.uuidString))
        XCTAssertEqual(session.title, "hablar")
    }

    func testOnlyReadAndWriteCapabilitiesAreInTheManual() async {
        let script = Script([reply("Hi.")])
        let session = makeSession(script)
        await session.send("hello")
        XCTAssertTrue(script.systems[0].contains("library.words"))
        XCTAssertTrue(script.systems[0].contains("words.add"))
        XCTAssertFalse(script.systems[0].contains("storage.get"))
        XCTAssertFalse(script.systems[0].contains("ai.generate"))
    }
}
