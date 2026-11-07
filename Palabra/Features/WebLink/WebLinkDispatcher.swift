import Foundation

/// Answers the web page's requests with the app's data, through the same capability registry Artifacts use.
/// Reads run only if the capability is on `readAllowList` and the registry itself says it is a read.
/// Writes (phase 4) run only if on `writeAllowList` and the registry says it is a write; each carries an id so a retry
/// after a lost reply is answered with the first result. AI runs only through the separate `ai` message, one capability.
/// Everything else (storage, anything that deletes, anything unknown) is refused with `forbidden`. API keys are not
/// reachable through any of these capabilities.
struct WebLinkDispatcher: Sendable {
    /// What the web UI may read. A name here that turns out to be a write in the registry is still refused.
    static let readAllowList: Set<String> = [
        "library.words", "library.word", "study.decks", "review.list", "stats.wordsPerDay", "stats.wordsPerWeek",
    ]

    /// What the web UI may change. Small on purpose: adding words, placing them in a section or tags, flagging for review.
    /// No deletes and no `storage.*` (the Storage page keeps live files read-only).
    static let writeAllowList: Set<String> = ["words.add", "words.place", "review.flag"]
    /// The one AI capability the page may ask for, only through the `ai` message and only while the link is live.
    static let aiCapability = "ai.generate"

    /// The reads that make up the first snapshot, with the arguments each is called with.
    static let snapshotReads: [(key: String, capability: String, args: JSONValue)] = [
        ("words", "library.words", .object(["limit": .number(500)])),
        ("decks", "study.decks", .object([:])),
        ("review", "review.list", .object([:])),
        ("wordsPerDay", "stats.wordsPerDay", .object([:])),
        ("wordsPerWeek", "stats.wordsPerWeek", .object([:])),
    ]

    let registry: CapabilityRegistry
    let now: @Sendable () -> Date
    let recent: RecentActions
    /// Optional: without it the page sees no artifacts (`artifacts` answers an empty list).
    let artifacts: WebArtifactReader?
    /// The live placement of a word (section and tags), for the conflict check on `words.place`. `nil` = no such word.
    let placement: @Sendable (_ idOrKey: String) async -> (category: String?, tags: [String])?

    init(
        registry: CapabilityRegistry,
        now: @escaping @Sendable () -> Date = { Date() },
        recent: RecentActions = RecentActions(),
        artifacts: WebArtifactReader? = nil,
        placement: @escaping @Sendable (_ idOrKey: String) async -> (category: String?, tags: [String])? = { _ in nil }
    ) {
        self.registry = registry
        self.now = now
        self.recent = recent
        self.artifacts = artifacts
        self.placement = placement
    }

    /// One reply to one request. `nil` means the type is not ours (unknown types are ignored, not answered).
    func handle(_ message: LinkMessage) async -> LinkMessage? {
        switch message.type {
        case "read": return await read(message)
        case "snapshot": return await snapshot(message)
        case "write": return await write(message)
        case "ai": return await ai(message)
        case "artifacts": return await artifactList(message)
        case "artifact": return await artifactPage(message)
        default: return nil
        }
    }

    private func read(_ message: LinkMessage) async -> LinkMessage {
        guard case .object(let payload)? = message.payload, let name = payload["capability"]?.stringValue else {
            return reject(message, reason: "bad-request")
        }
        switch await call(name, args: payload["args"] ?? .object([:])) {
        case .success(let value): return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": value]))
        case .failure(let refusal): return reject(message, reason: refusal.reason)
        }
    }

    private func snapshot(_ message: LinkMessage) async -> LinkMessage {
        var parts: [String: JSONValue] = [:]
        for read in Self.snapshotReads {
            switch await call(read.capability, args: read.args) {
            case .success(let value): parts[read.key] = value
            case .failure(let refusal): return reject(message, reason: refusal.reason) // all or nothing: a half snapshot would look complete
            }
        }
        let iso = ISO8601DateFormatter().string(from: now())
        return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["snapshot": .object(parts), "takenAt": .string(iso)]))
    }

    /// Why a read did not happen: the short code the page receives. (`Result` needs an `Error`; a bare String is not one.)
    private struct Refusal: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

    /// Allow-list, then the registry's own class check, then the call. Failure is a short reason code for the page.
    private func call(_ name: String, args: JSONValue) async -> Result<JSONValue, Refusal> {
        guard Self.readAllowList.contains(name) else { return .failure(Refusal("forbidden")) }
        guard let capability = registry.capability(named: name), capability.kind == .read else { return .failure(Refusal("forbidden")) }
        let session = ArtifactSession(artifactID: nil, dryRun: false)
        switch await registry.call(name: name, args: args, session: session, granted: [name]) {
        case .success(let value): return .success(value)
        case .failure(.badArgs): return .failure(Refusal("bad-args"))
        case .failure(.rateLimited): return .failure(Refusal("rate-limited"))
        case .failure: return .failure(Refusal("failed"))
        }
    }

    /// A change from the page: `{id, capability, args, base}`. Order of checks: shape, allow-list, registry class, a repeat of
    /// an action already run (answer with the first result), the conflict check, then the call.
    private func write(_ message: LinkMessage) async -> LinkMessage {
        guard case .object(let payload)? = message.payload,
              let actionID = payload["id"]?.stringValue, !actionID.isEmpty, actionID.count <= 80,
              let name = payload["capability"]?.stringValue else { return reject(message, reason: "bad-request") }
        guard Self.writeAllowList.contains(name),
              let capability = registry.capability(named: name), capability.kind == .write else { return reject(message, reason: "forbidden") }
        if let first = recent.reply(for: actionID) {
            return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": first, "repeat": .bool(true)]))
        }
        let args = payload["args"] ?? .object([:])
        if name == "words.place", let conflict = await placementConflict(args: args, base: payload["base"]) { return reject(message, reason: conflict) }
        let session = ArtifactSession(artifactID: nil, dryRun: false)
        switch await registry.call(name: name, args: args, session: session, granted: [name]) {
        case .success(let value):
            recent.remember(id: actionID, reply: value)
            return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": value]))
        case .failure(.badArgs): return reject(message, reason: "bad-args")
        case .failure(.rateLimited): return reject(message, reason: "rate-limited")
        case .failure: return reject(message, reason: "failed")
        }
    }

    /// `words.place` carries `base`, a map of word id/key to the placement token the page saw. A word whose live token
    /// differs, or that is gone, refuses the whole action (`conflict` / `not-found`): nothing is half applied.
    /// A missing `base` (a retry the person chose to force) skips the check.
    private func placementConflict(args: JSONValue, base: JSONValue?) async -> String? {
        guard case .object(let seen)? = base else { return nil }
        guard case .object(let object) = args, let items = object["words"]?.arrayValue else { return nil }
        for item in items {
            guard let ref = item["id"]?.stringValue ?? item["key"]?.stringValue, let expected = seen[ref]?.stringValue else { continue }
            guard let live = await placement(ref) else { return "not-found" }
            if PlacementToken.make(category: live.category, tags: live.tags) != expected { return "conflict" }
        }
        return nil
    }

    /// The artifact list. Without a reader the answer is an empty list, not an error.
    private func artifactList(_ message: LinkMessage) async -> LinkMessage {
        let list = await artifacts?.listPayload() ?? .array([])
        return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": list]))
    }

    /// One artifact page by id. Apps, unknown ids and undecodable specs all answer `not-found`: the page learns nothing more.
    private func artifactPage(_ message: LinkMessage) async -> LinkMessage {
        guard case .object(let payload)? = message.payload, let id = payload["id"]?.stringValue, id.count <= 80 else { return reject(message, reason: "bad-request") }
        guard let page = await artifacts?.page(id: id) else { return reject(message, reason: "not-found") }
        return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": page]))
    }

    /// An AI request from the page: `{args}` for `ai.generate`. Same rules as any capability call (the registry's own
    /// limits and the user's configured model apply); the page cannot name another capability and nothing is queued.
    private func ai(_ message: LinkMessage) async -> LinkMessage {
        guard case .object(let payload)? = message.payload else { return reject(message, reason: "bad-request") }
        guard let capability = registry.capability(named: Self.aiCapability), capability.kind == .ai else { return reject(message, reason: "forbidden") }
        let session = ArtifactSession(artifactID: nil, dryRun: false)
        switch await registry.call(name: Self.aiCapability, args: payload["args"] ?? .object([:]), session: session, granted: [Self.aiCapability]) {
        case .success(let value): return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": value]))
        case .failure(.badArgs): return reject(message, reason: "bad-args")
        case .failure(.rateLimited): return reject(message, reason: "rate-limited")
        case .failure: return reject(message, reason: "failed")
        }
    }

    private func reject(_ message: LinkMessage, reason: String) -> LinkMessage {
        LinkMessage(id: message.id, type: "reject", version: 1, payload: .object(["reason": .string(reason)]))
    }
}
