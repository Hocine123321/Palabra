import Foundation
import Observation

/// One open conversation: sends messages, runs the assistant loop (model call → reads run at once,
/// writes wait for the person's approval → model call with the results) and saves after every step.
@MainActor
@Observable
final class ChatSession {
    enum Phase: Equatable { case idle, thinking, running }

    /// (prompt, system instruction) -> the raw reply. The app supplies the key, model and retries.
    typealias Generate = @MainActor (_ prompt: String, _ system: String) async -> Result<String, AIError>

    let conversationID: UUID
    private(set) var title: String
    private(set) var turns: [ChatTurn]
    private(set) var phase: Phase = .idle
    var draft: String = ""

    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let registry: CapabilityRegistry
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private let language: @MainActor () -> SupportedLanguage
    @ObservationIgnored private let linkedWord: (id: UUID, title: String)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sessionID = UUID()
    @ObservationIgnored private let allowedNames: Set<String>

    init(
        conversation: ChatConversation,
        repository: ChatRepository,
        registry: CapabilityRegistry,
        language: @escaping @MainActor () -> SupportedLanguage,
        now: @escaping () -> Date = { Date() },
        generate: @escaping Generate
    ) {
        conversationID = conversation.id
        title = conversation.title
        turns = conversation.turns
        linkedWord = conversation.wordID.map { (id: $0, title: conversation.title) }
        self.repository = repository
        self.registry = registry
        self.language = language
        self.now = now
        self.generate = generate
        allowedNames = Set(registry.all.filter { $0.kind == .read || $0.kind == .write }.map(\.name))
    }

    var isBusy: Bool { phase != .idle }

    /// True when the chat was opened from a word's page.
    var isLinkedToWord: Bool { linkedWord != nil }

    /// Index of the turn whose writes wait for the person (only ever the last turn).
    private var pendingTurnIndex: Int? {
        guard let last = turns.indices.last, turns[last].actions.contains(where: { $0.state == .pending }) else { return nil }
        return last
    }

    var hasPending: Bool { pendingTurnIndex != nil }

    // MARK: - Person's actions

    func send(_ text: String? = nil) async {
        let trimmed = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        draft = ""
        // Typing on instead of tapping a card means "not that".
        if let index = pendingTurnIndex { markPending(in: index, as: .declined) }
        turns.append(ChatTurn(role: .user, text: String(trimmed.prefix(ChatLimits.maxTextLength)), createdAt: now()))
        if title == ChatConversation.defaultTitle, linkedWord == nil {
            title = String(trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(ChatLimits.maxTitleLength))
        }
        persist()
        await run()
    }

    func retry() async {
        guard !isBusy, let last = turns.last, last.status == .failed else { return }
        turns.removeLast()
        persist()
        await run()
    }

    func approvePending() async {
        guard !isBusy, let turnIndex = pendingTurnIndex else { return }
        phase = .running
        for actionIndex in turns[turnIndex].actions.indices where turns[turnIndex].actions[actionIndex].state == .pending {
            await execute(actionAt: actionIndex, inTurnAt: turnIndex)
        }
        persist()
        await run()
    }

    func declinePending() async {
        guard !isBusy, let turnIndex = pendingTurnIndex else { return }
        markPending(in: turnIndex, as: .declined)
        persist()
        await run()
    }

    func clear() {
        guard !isBusy else { return }
        turns = []
        persist()
    }

    // MARK: - The loop

    private func run() async {
        defer { phase = .idle }
        for _ in 0..<ChatLimits.maxRoundsPerMessage {
            phase = .thinking
            let system = ChatPrompts.systemInstruction(manual: registry.manual(including: [.read, .write]), language: language(), linkedWord: linkedWord)
            let prompt = ChatPrompts.transcript(turns: turns)
            let reply: ChatReply
            switch await generate(prompt, system) {
            case .failure(let error):
                appendFailure(error)
                return
            case .success(let raw):
                switch ChatReplyParser.parse(raw) {
                case .success(let parsed):
                    reply = parsed
                case .failure(let problem):
                    // One automatic retry with the concrete problem; then fall back to the text alone.
                    switch await generate(prompt + ChatPrompts.retryAddendum(problem.detail), system) {
                    case .failure(let error):
                        appendFailure(error)
                        return
                    case .success(let second):
                        switch ChatReplyParser.parse(second) {
                        case .success(let parsed): reply = parsed
                        case .failure: reply = ChatReplyParser.textOnly(second)
                        }
                    }
                }
            }
            let actions = reply.calls.map(makeAction)
            if reply.say.isEmpty && actions.isEmpty {
                appendFailure(.malformedResponse)
                return
            }
            turns.append(ChatTurn(role: .assistant, text: String(reply.say.prefix(ChatLimits.maxTextLength)), createdAt: now(), actions: actions))
            persist()
            if actions.isEmpty { return }

            phase = .running
            let turnIndex = turns.count - 1
            for actionIndex in actions.indices where turns[turnIndex].actions[actionIndex].state == .pending && !turns[turnIndex].actions[actionIndex].isWrite {
                await execute(actionAt: actionIndex, inTurnAt: turnIndex)
            }
            persist()
            if pendingTurnIndex != nil { return } // waits for the person
        }
    }

    private func makeAction(_ call: ChatCall) -> ChatAction {
        let argsJSON = call.args.jsonString
        guard let capability = registry.capability(named: call.capability), allowedNames.contains(capability.name) else {
            return ChatAction(capability: call.capability, argsJSON: argsJSON, summary: call.capability, isWrite: false, state: .failed, result: "unknown capability")
        }
        return ChatAction(
            capability: capability.name,
            argsJSON: argsJSON,
            summary: capability.describe?(call.args) ?? capability.name,
            isWrite: capability.kind == .write,
            state: .pending
        )
    }

    private func execute(actionAt actionIndex: Int, inTurnAt turnIndex: Int) async {
        let action = turns[turnIndex].actions[actionIndex]
        let args = (try? JSONDecoder().decode(JSONValue.self, from: Data(action.argsJSON.utf8))) ?? .object([:])
        let result = await registry.call(
            name: action.capability,
            args: args,
            session: ArtifactSession(artifactID: nil, dryRun: false, sessionID: sessionID),
            granted: allowedNames
        )
        guard turns.indices.contains(turnIndex), turns[turnIndex].actions.indices.contains(actionIndex), turns[turnIndex].actions[actionIndex].id == action.id else { return }
        switch result {
        case .success(let value):
            turns[turnIndex].actions[actionIndex].state = .applied
            turns[turnIndex].actions[actionIndex].result = String(value.jsonString.prefix(ChatLimits.maxResultLength))
        case .failure(let error):
            turns[turnIndex].actions[actionIndex].state = .failed
            turns[turnIndex].actions[actionIndex].result = Self.text(for: error)
        }
    }

    private func markPending(in turnIndex: Int, as state: ChatAction.State) {
        for actionIndex in turns[turnIndex].actions.indices where turns[turnIndex].actions[actionIndex].state == .pending {
            turns[turnIndex].actions[actionIndex].state = state
        }
    }

    private func appendFailure(_ error: AIError) {
        turns.append(ChatTurn(role: .assistant, text: "", createdAt: now(), status: .failed, errorText: error.userMessage))
        persist()
    }

    private func persist() {
        repository.save(id: conversationID, turns: turns, title: title, now: now())
    }

    static func text(for error: CapabilityError) -> String {
        switch error {
        case .unknown: return "unknown capability"
        case .notGranted: return "not allowed"
        case .badArgs(let message): return "bad arguments: \(message)"
        case .failed(let message): return message
        case .rateLimited: return "rate limited"
        }
    }
}
