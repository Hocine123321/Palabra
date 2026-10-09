import XCTest
@testable import Palabra

final class AssistantSettingsTests: XCTestCase {
    func testDefaults() {
        let s = AssistantSettings.default
        XCTAssertEqual(s.replyLength, .balanced)
        XCTAssertTrue(s.askBeforeChanging)
        XCTAssertTrue(s.disabledGroups.isEmpty)
        XCTAssertEqual(s.customInstructions, "")
        for group in AssistantToolGroup.allCases { XCTAssertTrue(s.isEnabled(group)) }
    }

    func testRoundTrip() throws {
        var s = AssistantSettings()
        s.replyLength = .detailed
        s.askBeforeChanging = false
        s.set(.study, enabled: false)
        s.set(.words, enabled: false)
        s.customInstructions = "add an example"
        let back = try JSONDecoder().decode(AssistantSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testDecodingIsTolerant() throws {
        let empty = try JSONDecoder().decode(AssistantSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .default)
        let json = #"{"replyLength":"nonsense","disabledGroups":["study","from-the-future"],"customInstructions":"  hi  "}"#
        let s = try JSONDecoder().decode(AssistantSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.replyLength, .balanced)
        XCTAssertEqual(s.disabledGroups, [.study])
        XCTAssertEqual(s.customInstructions, "hi")
        XCTAssertTrue(s.askBeforeChanging)
    }

    func testInstructionsAreCapped() {
        let long = String(repeating: "x", count: 900)
        XCTAssertEqual(AssistantSettings.cleaned(long).count, AssistantSettings.maxInstructionsLength)
    }

    func testCapabilitiesMapToGroups() {
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "library.words"), .library)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "library.word"), .library)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "stats.wordsPerDay"), .library)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "words.add"), .words)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "words.place"), .words)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "study.addCards"), .study)
        XCTAssertEqual(AssistantToolGroup.group(forCapability: "review.flag"), .review)
        XCTAssertNil(AssistantToolGroup.group(forCapability: "something.else"))
    }

    func testAllowsFollowsGroupSwitches() {
        var s = AssistantSettings()
        s.set(.words, enabled: false)
        XCTAssertFalse(s.allows(capability: "words.add"))
        XCTAssertTrue(s.allows(capability: "library.words"))
        XCTAssertTrue(s.allows(capability: "something.else"))
        s.set(.words, enabled: true)
        XCTAssertTrue(s.allows(capability: "words.add"))
    }

    func testStorePersistsAndFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "assist-\(UUID().uuidString)")!
        XCTAssertEqual(SettingsStore(defaults: defaults).assistantSettings, .default)
        var s = AssistantSettings()
        s.askBeforeChanging = false
        s.set(.review, enabled: false)
        SettingsStore(defaults: defaults).assistantSettings = s
        XCTAssertEqual(SettingsStore(defaults: defaults).assistantSettings, s)
    }

    // MARK: prompt

    func testPromptCarriesReplyLengthAndInstructions() {
        var s = AssistantSettings()
        s.replyLength = .concise
        s.customInstructions = "Always add an example."
        let text = ChatPrompts.systemInstruction(manual: "", language: .english, linkedWord: nil, settings: s)
        XCTAssertTrue(text.contains(AssistantSettings.ReplyLength.concise.promptHint))
        XCTAssertTrue(text.contains("Always add an example."))
        XCTAssertFalse(text.contains(AssistantSettings.ReplyLength.detailed.promptHint))
        let plain = ChatPrompts.systemInstruction(manual: "", language: .english, linkedWord: nil)
        XCTAssertFalse(plain.contains("standing instructions"))
        XCTAssertTrue(plain.contains("approves or declines"))
    }

    func testPromptSaysWritesApplyImmediatelyWhenAutoApplying() {
        let text = ChatPrompts.systemInstruction(manual: "", language: .english, linkedWord: nil, autoApplies: true)
        XCTAssertTrue(text.contains("applied immediately"))
        XCTAssertFalse(text.contains("approves or declines"))
    }
}

// MARK: - Session behaviour

@MainActor
private final class SettingsScript {
    var replies: [Result<String, AIError>]
    private(set) var systems: [String] = []
    private(set) var prompts: [String] = []
    init(_ replies: [Result<String, AIError>]) { self.replies = replies }
    func next(prompt: String, system: String) -> Result<String, AIError> {
        prompts.append(prompt)
        systems.append(system)
        return replies.isEmpty ? .success("(script empty)") : replies.removeFirst()
    }
}

@MainActor
private final class SettingsBox { var value = AssistantSettings() }

@MainActor
final class ChatSessionSettingsTests: XCTestCase {
    private var repository: SwiftDataChatRepository!
    private var readBox: CallBox!
    private var writeBox: CallBox!
    private var registry: CapabilityRegistry!
    private let box = SettingsBox()

    override func setUp() {
        repository = SwiftDataChatRepository.inMemory()
        readBox = CallBox()
        writeBox = CallBox()
        registry = CapabilityRegistry([
            makeCapability("library.words", .read, box: readBox, result: .array([.string("hola")])),
            makeCapability("words.add", .write, box: writeBox, result: .object(["queued": .number(2)])),
            makeCapability("study.addCards", .write),
        ])
    }

    private func makeSession(_ script: SettingsScript) -> ChatSession {
        let conversation = repository.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date(timeIntervalSince1970: 0))
        let box = self.box
        return ChatSession(
            conversation: conversation,
            repository: repository,
            registry: registry,
            language: { .english },
            settings: { box.value },
            generate: { prompt, system in script.next(prompt: prompt, system: system) }
        )
    }

    private func reply(_ text: String, calls: String) -> Result<String, AIError> { .success("\(text)\n---ACTIONS---\n\(calls)") }
    private let writeCall = #"[{"capability":"words.add","args":{"words":["a","b"]}}]"#

    func testAutoApplyRunsWritesWithoutWaiting() async {
        box.value.askBeforeChanging = false
        let script = SettingsScript([reply("Adding.", calls: writeCall), .success("Done.")])
        let session = makeSession(script)
        await session.send("add words")
        XCTAssertTrue(writeBox.called)
        XCTAssertFalse(session.hasPending)
        XCTAssertEqual(session.turns[1].actions.first?.state, .applied)
        XCTAssertEqual(script.prompts.count, 2)
        XCTAssertEqual(session.turns.last?.text, "Done.")
        XCTAssertTrue(script.systems[0].contains("applied immediately"))
    }

    func testAskingIsTheDefault() async {
        let script = SettingsScript([reply("Adding.", calls: writeCall)])
        let session = makeSession(script)
        await session.send("add words")
        XCTAssertTrue(session.hasPending)
        XCTAssertFalse(writeBox.called)
    }

    func testSwitchedOffGroupIsHiddenFromTheManualAndRefused() async {
        box.value.set(.words, enabled: false)
        let script = SettingsScript([reply("Adding.", calls: writeCall), .success("I can't do that.")])
        let session = makeSession(script)
        await session.send("add words")
        XCTAssertFalse(script.systems[0].contains("words.add"))
        XCTAssertTrue(script.systems[0].contains("library.words"))
        XCTAssertFalse(writeBox.called)
        XCTAssertEqual(session.turns[1].actions.first?.state, .failed)
        XCTAssertTrue(script.prompts[1].contains("-> failed: switched off in Settings"))
    }

    func testSwitchingOffAfterTheProposalBlocksTheApproval() async {
        let script = SettingsScript([reply("Adding.", calls: writeCall), .success("Could not.")])
        let session = makeSession(script)
        await session.send("add words")
        XCTAssertTrue(session.hasPending)
        box.value.set(.words, enabled: false)
        await session.approvePending()
        XCTAssertFalse(writeBox.called)
        XCTAssertEqual(session.turns[1].actions.first?.state, .failed)
        XCTAssertEqual(session.turns[1].actions.first?.result, "not allowed")
    }

    func testReplyStyleReachesTheSystemInstruction() async {
        box.value.replyLength = .detailed
        box.value.customInstructions = "Use formal Spanish."
        let script = SettingsScript([.success("Hola.")])
        let session = makeSession(script)
        await session.send("hi")
        XCTAssertTrue(script.systems[0].contains(AssistantSettings.ReplyLength.detailed.promptHint))
        XCTAssertTrue(script.systems[0].contains("Use formal Spanish."))
    }
}
