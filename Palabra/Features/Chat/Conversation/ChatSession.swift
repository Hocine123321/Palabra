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
    /// The same call with a photo attached.
    typealias GenerateWithImage = @MainActor (_ prompt: String, _ system: String, _ image: AIImage) async -> Result<String, AIError>
    /// Reads the text of a photo on this device (Settings → Assistant → Photos).
    typealias ReadPhoto = @Sendable (_ imageData: Data) async -> Result<String, RecognitionError>

    let conversationID: UUID
    private(set) var title: String
    private(set) var turns: [ChatTurn]
    private(set) var phase: Phase = .idle
    /// True once a reply has taken longer than `ChatLimits.slowAfter` seconds of our own waiting (not counting a question
    /// that waits for the person), so the screen can say so and offer Stop.
    private(set) var isSlow = false
    /// A one-line explanation of what the assistant is doing when it is not the plain first attempt.
    private(set) var statusNote: String?
    var draft: String = ""
    /// A photo waiting to be sent with the next message, and why the last one could not be attached.
    private(set) var attachment: ChatAttachment?
    private(set) var attachmentProblem: String?

    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let registry: CapabilityRegistry
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private let generateWithImage: GenerateWithImage?
    /// The latest photo of this chat, kept in memory so follow-up messages ("add the first five") still see it.
    @ObservationIgnored private var currentPhoto: AIImage?
    @ObservationIgnored private let language: @MainActor () -> SupportedLanguage
    @ObservationIgnored private let linkedWord: (id: UUID, title: String)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sessionID = UUID()
    @ObservationIgnored private let settings: @MainActor () -> AssistantSettings
    @ObservationIgnored private let chatCapabilityNames: Set<String>
    /// Seconds a reply may take before the app gives up on it (counted only while the app is the one waiting).
    @ObservationIgnored private let replyDeadline: Int
    /// A question for the person (a retry card) is open: the clock pauses, because the wait is theirs.
    @ObservationIgnored private let isWaitingOnPerson: @MainActor () -> Bool
    /// One second of the watchdog clock; tests make it instant.
    @ObservationIgnored private let tick: @Sendable () async -> Void
    /// After a failed reply, try once more with a shorter conversation and no photo.
    @ObservationIgnored private let lightFallback: Bool
    @ObservationIgnored private let readPhotoOnDevice: ReadPhoto?
    @ObservationIgnored private var activeRace: CallRace?
    @ObservationIgnored private var activeWork: Task<Void, Never>?

    init(
        conversation: ChatConversation,
        repository: ChatRepository,
        registry: CapabilityRegistry,
        language: @escaping @MainActor () -> SupportedLanguage,
        settings: @escaping @MainActor () -> AssistantSettings = { .default },
        now: @escaping () -> Date = { Date() },
        generateWithImage: GenerateWithImage? = nil,
        replyDeadline: Int = ChatLimits.replyDeadline,
        lightFallback: Bool = false,
        readPhotoOnDevice: ReadPhoto? = nil,
        isWaitingOnPerson: @escaping @MainActor () -> Bool = { false },
        tick: @escaping @Sendable () async -> Void = { try? await Task.sleep(nanoseconds: 1_000_000_000) },
        generate: @escaping Generate
    ) {
        self.replyDeadline = replyDeadline
        self.lightFallback = lightFallback
        self.readPhotoOnDevice = readPhotoOnDevice
        self.isWaitingOnPerson = isWaitingOnPerson
        self.tick = tick
        conversationID = conversation.id
        title = conversation.title
        turns = conversation.turns
        linkedWord = conversation.wordID.map { (id: $0, title: conversation.title) }
        self.repository = repository
        self.registry = registry
        self.language = language
        self.settings = settings
        self.now = now
        self.generate = generate
        self.generateWithImage = generateWithImage
        chatCapabilityNames = Set(registry.all.filter { $0.kind == .read || $0.kind == .write }.map(\.name))
    }

    /// Read + write capabilities whose group is switched on right now (checked per call, so a change in Settings applies at once).
    private var allowedNames: Set<String> {
        let current = settings()
        return chatCapabilityNames.filter { current.allows(capability: $0) }
    }

    var isBusy: Bool { phase != .idle }

    /// True when the app can read photos (a key and a model are available to send them with).
    var canAttachPhotos: Bool { generateWithImage != nil }

    /// True when the chat was opened from a word's page.
    var isLinkedToWord: Bool { linkedWord != nil }

    /// Index of the turn whose writes wait for the person (only ever the last turn).
    private var pendingTurnIndex: Int? {
        guard let last = turns.indices.last, turns[last].actions.contains(where: { $0.state == .pending }) else { return nil }
        return last
    }

    var hasPending: Bool { pendingTurnIndex != nil }

    // MARK: - Person's actions

    /// Prepares a photo (from the library or the camera) to go with the next message.
    func attachPhoto(_ data: Data) async {
        attachmentProblem = nil
        let prepared = await Task.detached(priority: .userInitiated) {
            (full: PhotoPreparer.prepare(data, maxPixelSize: ChatLimits.photoPixelSize),
             thumbnail: PhotoPreparer.prepare(data, maxPixelSize: ChatLimits.thumbnailPixelSize))
        }.value
        guard let full = prepared.full, let thumbnail = prepared.thumbnail else {
            attachmentProblem = "That photo could not be read."
            return
        }
        attachment = ChatAttachment(image: full, thumbnail: thumbnail.data)
    }

    func removeAttachment() {
        attachment = nil
        attachmentProblem = nil
    }

    func send(_ text: String? = nil) async {
        let trimmed = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = generateWithImage == nil ? nil : attachment
        guard !trimmed.isEmpty || photo != nil, !isBusy else { return }

        // Who reads the photo: this phone (only its text is sent) or the model (the photo is sent).
        var photoText: String?
        var imageForModel = photo?.image
        let reading = settings().photoReading
        if let photo, reading != .model, let read = readPhotoOnDevice {
            phase = .thinking
            statusNote = "Reading the photo on your phone…"
            let outcome = await read(photo.image.data)
            phase = .idle
            statusNote = nil
            switch outcome {
            case .success(let found):
                photoText = String(found.prefix(ChatLimits.maxPhotoTextLength))
                imageForModel = nil
            case .failure(let failure):
                if reading == .onDevice {
                    // Nothing leaves the phone, so there is nothing to send: the message and photo stay for another try.
                    attachmentProblem = failure.userMessage
                    return
                }
                // On-device first, and it found nothing: the model gets the photo.
            }
        }

        draft = ""
        attachment = nil
        attachmentProblem = nil
        if let imageForModel {
            currentPhoto = imageForModel
        } else if photo != nil {
            // A new photo read on the phone replaces the last one the model was given.
            currentPhoto = nil
        }
        // Typing on instead of tapping a card means "not that".
        if let index = pendingTurnIndex { markPending(in: index, as: .declined) }
        turns.append(ChatTurn(role: .user, text: String(trimmed.prefix(ChatLimits.maxTextLength)), createdAt: now(), thumbnail: photo?.thumbnail, photoText: photoText))
        if title == ChatConversation.defaultTitle, linkedWord == nil {
            let source = trimmed.isEmpty ? "Photo" : trimmed
            title = String(source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(ChatLimits.maxTitleLength))
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

    /// The person tapped Stop: the reply being waited for is abandoned at once and the turn can be retried.
    func stop() {
        guard let activeRace else { return }
        activeRace.resolve(.failure(.cancelled))
        activeWork?.cancel()
    }

    /// Coming back to a chat that kept running (or finished) while its screen was closed: show what is saved, unless a
    /// reply is still on its way (then the live state is the truth).
    func reload(from conversation: ChatConversation) {
        guard !isBusy else { return }
        turns = conversation.turns
        title = conversation.title
    }

    func clear() {
        guard !isBusy else { return }
        turns = []
        currentPhoto = nil
        persist()
    }

    // MARK: - The loop

    private func run() async {
        defer {
            phase = .idle
            isSlow = false
            statusNote = nil
        }
        for _ in 0..<ChatLimits.maxRoundsPerMessage {
            phase = .thinking
            let current = settings()
            let allowed = allowedNames
            let system = ChatPrompts.systemInstruction(
                manual: registry.manual(including: [.read, .write], only: allowed),
                language: language(),
                linkedWord: linkedWord,
                settings: current,
                autoApplies: !current.askBeforeChanging,
                hasPhoto: currentPhoto != nil && generateWithImage != nil,
                hasPhotoText: turns.contains { $0.photoText != nil }
            )
            let prompt = ChatPrompts.transcript(turns: turns)
            let photo = generateWithImage == nil ? nil : currentPhoto
            let plain = generate, withImage = generateWithImage
            let call: (String) async -> Result<String, AIError> = { [self] text in
                await timed {
                    if let photo, let withImage { return await withImage(text, system, photo) }
                    return await plain(text, system)
                }
            }
            let reply: ChatReply
            var outcome = await call(prompt)
            // A reply that could not be had: one lighter attempt (short conversation, no photo) before giving up.
            if case .failure(let error) = outcome, lightFallback, Self.worthALighterTry(error) {
                statusNote = "Trying a lighter request…"
                let lightSystem = ChatPrompts.systemInstruction(
                    manual: registry.manual(including: [.read, .write], only: allowed),
                    language: language(), linkedWord: linkedWord, settings: current,
                    autoApplies: !current.askBeforeChanging, hasPhoto: false,
                    hasPhotoText: turns.contains { $0.photoText != nil }
                )
                let light = ChatPrompts.transcript(turns: turns, budget: ChatLimits.lightTranscriptBudget)
                outcome = await timed { await plain(light, lightSystem) }
                statusNote = nil
            }
            switch outcome {
            case .failure(let error):
                appendFailure(error)
                return
            case .success(let raw):
                switch ChatReplyParser.parse(raw) {
                case .success(let parsed):
                    reply = parsed
                case .failure(let problem):
                    // One automatic retry with the concrete problem; then fall back to the text alone.
                    switch await call(prompt + ChatPrompts.retryAddendum(problem.detail)) {
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
            let autoApply = !current.askBeforeChanging
            for actionIndex in actions.indices where turns[turnIndex].actions[actionIndex].state == .pending && (autoApply || !turns[turnIndex].actions[actionIndex].isWrite) {
                await execute(actionAt: actionIndex, inTurnAt: turnIndex)
            }
            persist()
            if pendingTurnIndex != nil { return } // waits for the person
        }
    }

    private func makeAction(_ call: ChatCall) -> ChatAction {
        let argsJSON = call.args.jsonString
        guard let capability = registry.capability(named: call.capability), chatCapabilityNames.contains(capability.name) else {
            return ChatAction(capability: call.capability, argsJSON: argsJSON, summary: call.capability, isWrite: false, state: .failed, result: "unknown capability")
        }
        guard allowedNames.contains(capability.name) else {
            return ChatAction(capability: capability.name, argsJSON: argsJSON, summary: capability.name, isWrite: capability.kind == .write, state: .failed, result: "switched off in Settings")
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
        let text: String
        switch error {
        case .cancelled: text = "Stopped. Tap Retry to send it again."
        case .timeout: text = "The assistant didn't answer in time. Tap Retry, or try a shorter message."
        default: text = error.userMessage
        }
        turns.append(ChatTurn(role: .assistant, text: "", createdAt: now(), status: .failed, errorText: text))
        persist()
    }

    /// Failures a smaller request can get past (slowness, a hiccup, a reply that could not be read); not a missing key.
    static func worthALighterTry(_ error: AIError) -> Bool {
        switch error {
        case .timeout, .serverError, .truncated, .malformedResponse, .validationFailed, .unknown: return true
        default: return false
        }
    }

    /// One model call with a watchdog: it ends with whatever comes first, the answer, the deadline, or Stop. The call
    /// itself is cancelled, but the wait never depends on the call being polite about it.
    private func timed(_ operation: @escaping @MainActor () async -> Result<String, AIError>) async -> Result<String, AIError> {
        let race = CallRace()
        let work = Task { @MainActor in race.resolve(await operation()) }
        activeRace = race
        activeWork = work
        isSlow = false
        let limit = replyDeadline
        let tick = tick
        let watchdog = Task { @MainActor [weak self] in
            var waited = 0
            while !Task.isCancelled {
                await tick()
                guard let self, !Task.isCancelled else { return }
                if self.isWaitingOnPerson() { continue }
                waited += 1
                if waited >= ChatLimits.slowAfter { self.isSlow = true }
                if waited >= limit {
                    race.resolve(.failure(.timeout))
                    work.cancel()
                    return
                }
            }
        }
        let result = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            Task { @MainActor in
                race.resolve(.failure(.cancelled))
                work.cancel()
            }
        }
        watchdog.cancel()
        work.cancel()
        activeRace = nil
        activeWork = nil
        isSlow = false
        return result
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

/// A photo prepared for the next message: the full picture that is sent, and a small copy that stays in the chat.
struct ChatAttachment: Equatable, Sendable {
    let image: AIImage
    let thumbnail: Data
}

/// Whichever of "the answer", "the deadline" and "Stop" happens first decides the result; later ones are ignored.
@MainActor
private final class CallRace {
    private var result: Result<String, AIError>?
    private var continuation: CheckedContinuation<Result<String, AIError>, Never>?

    func resolve(_ value: Result<String, AIError>) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    func value() async -> Result<String, AIError> {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
}
