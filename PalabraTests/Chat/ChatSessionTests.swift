import XCTest
import UIKit
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

/// A reply that never comes, a person who gives up waiting, and the lighter second try.
@MainActor
final class ChatWatchdogTests: XCTestCase {
    private var repository: SwiftDataChatRepository!

    override func setUp() {
        repository = SwiftDataChatRepository.inMemory()
    }

    private func makeSession(
        deadline: Int = 3,
        light: Bool = false,
        tick: @escaping @Sendable () async -> Void = { await Task.yield() },
        generate: @escaping ChatSession.Generate
    ) -> ChatSession {
        let conversation = repository.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date(timeIntervalSince1970: 0))
        return ChatSession(
            conversation: conversation, repository: repository, registry: CapabilityRegistry([]),
            language: { .english }, replyDeadline: deadline, lightFallback: light, tick: tick, generate: generate
        )
    }

    /// Sleeps until cancelled: a call that would hang for an hour.
    private static func hang() async -> Result<String, AIError> {
        try? await Task.sleep(nanoseconds: 3_600_000_000_000)
        return .failure(.cancelled)
    }

    func testASilentModelEndsInATimeoutInsteadOfThinkingForever() async {
        let session = makeSession { _, _ in await Self.hang() }
        await session.send("hello")
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(session.turns.last?.status, .failed)
        XCTAssertEqual(session.turns.last?.errorText, "The assistant didn't answer in time. Tap Retry, or try a shorter message.")
        XCTAssertFalse(session.isSlow)
    }

    func testStopEndsTheWaitAndRetryAsksAgain() async {
        final class Calls { var count = 0 }
        let calls = Calls()
        let session = makeSession(
            deadline: 100_000,
            tick: { try? await Task.sleep(nanoseconds: 5_000_000) },
            generate: { _, _ in
                calls.count += 1
                return calls.count == 1 ? await Self.hang() : .success("Hola otra vez.")
            }
        )
        let sending = Task { await session.send("hello") }
        while session.phase != .thinking { await Task.yield() }
        session.stop()
        await sending.value
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(session.turns.last?.status, .failed)
        XCTAssertEqual(session.turns.last?.errorText, "Stopped. Tap Retry to send it again.")
        await session.retry()
        XCTAssertEqual(session.turns.last?.text, "Hola otra vez.")
        XCTAssertEqual(calls.count, 2)
    }

    func testTheClockPausesWhileAQuestionWaitsForThePerson() async {
        final class Flag { var waiting = true }
        let flag = Flag()
        let conversation = repository.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date(timeIntervalSince1970: 0))
        let session = ChatSession(
            conversation: conversation, repository: repository, registry: CapabilityRegistry([]),
            language: { .english }, replyDeadline: 2,
            isWaitingOnPerson: { flag.waiting }, tick: { await Task.yield() },
            generate: { _, _ in
                // Many ticks pass while the person decides; the reply then arrives.
                for _ in 0..<200 { await Task.yield() }
                flag.waiting = false
                return .success("Hecho.")
            }
        )
        await session.send("hello")
        XCTAssertEqual(session.turns.last?.text, "Hecho.")
    }

    func testAFailedReplyGetsOneLighterTryWithAShorterConversation() async {
        final class Seen { var prompts: [String] = [] }
        let seen = Seen()
        let session = makeSession(light: true) { prompt, _ in
            seen.prompts.append(prompt)
            return seen.prompts.count == 1 ? .failure(.timeout) : .success("Aquí estoy.")
        }
        await session.send(String(repeating: "palabra ", count: 1_500))
        XCTAssertEqual(seen.prompts.count, 2)
        XCTAssertLessThan(seen.prompts[1].count, seen.prompts[0].count)
        XCTAssertEqual(session.turns.last?.text, "Aquí estoy.")
    }

    func testAKeyProblemIsNotRetriedLighter() async {
        final class Seen { var count = 0 }
        let seen = Seen()
        let session = makeSession(light: true) { _, _ in
            seen.count += 1
            return .failure(.invalidAPIKey)
        }
        await session.send("hello")
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(session.turns.last?.errorText, AIError.invalidAPIKey.userMessage)
    }
}

/// Who reads a chat photo: the model, or this phone.
@MainActor
final class ChatPhotoReadingTests: XCTestCase {
    private final class Log {
        var plain: [String] = []
        var withImage: [String] = []
        var reads = 0
    }

    private func jpeg() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
    }

    private func makeSession(
        _ mode: AssistantSettings.PhotoReading, log: Log, reading: Result<String, RecognitionError>
    ) -> ChatSession {
        let repository = SwiftDataChatRepository.inMemory()
        let conversation = repository.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date(timeIntervalSince1970: 0))
        var settings = AssistantSettings()
        settings.photoReading = mode
        return ChatSession(
            conversation: conversation, repository: repository, registry: CapabilityRegistry([]),
            language: { .english }, settings: { settings },
            generateWithImage: { prompt, _, _ in log.withImage.append(prompt); return .success("from the photo") },
            readPhotoOnDevice: { _ in log.reads += 1; return reading },
            generate: { prompt, _ in log.plain.append(prompt); return .success("from the text") }
        )
    }

    func testOnDeviceReadingSendsOnlyTheText() async {
        let log = Log()
        let session = makeSession(.onDevice, log: log, reading: .success("la casa\nel perro"))
        await session.attachPhoto(jpeg())
        await session.send("what are these?")
        XCTAssertEqual(log.reads, 1)
        XCTAssertTrue(log.withImage.isEmpty, "the photo itself never goes to the model")
        XCTAssertEqual(log.plain.count, 1)
        XCTAssertTrue(log.plain[0].contains("[Text read from the photo on the user's phone]\nla casa\nel perro"), log.plain[0])
        XCTAssertEqual(session.turns.first?.photoText, "la casa\nel perro")
        XCTAssertNotNil(session.turns.first?.thumbnail)
        XCTAssertEqual(session.turns.last?.text, "from the text")
    }

    func testTheTextStaysWithTheMessageForFollowUps() async {
        let log = Log()
        let session = makeSession(.onDevice, log: log, reading: .success("el gato"))
        await session.attachPhoto(jpeg())
        await session.send("add these")
        await session.send("and the first one again?")
        XCTAssertTrue(log.plain[1].contains("el gato"), "a later question still sees what the photo said")
        XCTAssertTrue(log.withImage.isEmpty)
    }

    func testOnDeviceFindingNothingSendsNothing() async {
        let log = Log()
        let session = makeSession(.onDevice, log: log, reading: .failure(.nothingFound))
        await session.attachPhoto(jpeg())
        session.draft = "read this"
        await session.send()
        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertTrue(log.plain.isEmpty && log.withImage.isEmpty)
        XCTAssertNotNil(session.attachment, "the photo stays so the person can retake it or change the setting")
        XCTAssertEqual(session.draft, "read this")
        XCTAssertEqual(session.attachmentProblem, RecognitionError.nothingFound.userMessage)
        XCTAssertEqual(session.phase, .idle)
    }

    func testPhoneFirstFallsBackToTheModelWhenNoTextIsFound() async {
        let log = Log()
        let session = makeSession(.onDeviceFirst, log: log, reading: .failure(.nothingFound))
        await session.attachPhoto(jpeg())
        await session.send("what is this?")
        XCTAssertEqual(log.reads, 1)
        XCTAssertEqual(log.withImage.count, 1, "the model reads it")
        XCTAssertNil(session.turns.first?.photoText)
    }

    func testPhoneFirstUsesThePhonesTextWhenItFindsSome() async {
        let log = Log()
        let session = makeSession(.onDeviceFirst, log: log, reading: .success("hola"))
        await session.attachPhoto(jpeg())
        await session.send("translate")
        XCTAssertTrue(log.withImage.isEmpty)
        XCTAssertEqual(session.turns.first?.photoText, "hola")
    }

    func testModelModeNeverTouchesThePhonesReader() async {
        let log = Log()
        let session = makeSession(.model, log: log, reading: .success("unused"))
        await session.attachPhoto(jpeg())
        await session.send("what is this?")
        XCTAssertEqual(log.reads, 0)
        XCTAssertEqual(log.withImage.count, 1)
        XCTAssertNil(session.turns.first?.photoText)
    }

    func testSettingsAndTurnsStayTolerant() throws {
        XCTAssertEqual(AssistantSettings.default.photoReading, .model)
        let unknown = try JSONDecoder().decode(AssistantSettings.self, from: Data(#"{"photoReading":"telepathy"}"#.utf8))
        XCTAssertEqual(unknown.photoReading, .model)
        var settings = AssistantSettings()
        settings.photoReading = .onDeviceFirst
        XCTAssertEqual(try JSONDecoder().decode(AssistantSettings.self, from: JSONEncoder().encode(settings)).photoReading, .onDeviceFirst)

        let old = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"user","text":"hi"}"#.utf8))
        XCTAssertNil(old.photoText)
        let turn = ChatTurn(role: .user, text: "x", photoText: "hola")
        XCTAssertEqual(try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn)).photoText, "hola")
    }
}
