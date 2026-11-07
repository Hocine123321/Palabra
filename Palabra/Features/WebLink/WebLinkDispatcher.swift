import Foundation

/// Answers the web page's requests with the app's data, through the same capability registry Artifacts use.
/// Phase 2 is read-only: only capabilities on `readAllowList` run, and only if the registry itself says they
/// are reads. Everything else (writes, AI, storage) is refused with `forbidden`, so the page cannot change
/// anything and cannot spend quota. API keys are not reachable through any of these capabilities.
struct WebLinkDispatcher: Sendable {
    /// What the web UI may read. A name here that turns out to be a write in the registry is still refused.
    static let readAllowList: Set<String> = [
        "library.words", "library.word", "study.decks", "review.list", "stats.wordsPerDay", "stats.wordsPerWeek",
    ]

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

    init(registry: CapabilityRegistry, now: @escaping @Sendable () -> Date = { Date() }) {
        self.registry = registry
        self.now = now
    }

    /// One reply to one request. `nil` means the type is not ours (unknown types are ignored, not answered).
    func handle(_ message: LinkMessage) async -> LinkMessage? {
        switch message.type {
        case "read": return await read(message)
        case "snapshot": return await snapshot(message)
        default: return nil
        }
    }

    private func read(_ message: LinkMessage) async -> LinkMessage {
        guard case .object(let payload)? = message.payload, let name = payload["capability"]?.stringValue else {
            return reject(message, reason: "bad-request")
        }
        switch await call(name, args: payload["args"] ?? .object([:])) {
        case .success(let value): return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["result": value]))
        case .failure(let reason): return reject(message, reason: reason)
        }
    }

    private func snapshot(_ message: LinkMessage) async -> LinkMessage {
        var parts: [String: JSONValue] = [:]
        for read in Self.snapshotReads {
            switch await call(read.capability, args: read.args) {
            case .success(let value): parts[read.key] = value
            case .failure(let reason): return reject(message, reason: reason) // all or nothing: a half snapshot would look complete
            }
        }
        let iso = ISO8601DateFormatter().string(from: now())
        return LinkMessage(id: message.id, type: "ack", version: 1, payload: .object(["snapshot": .object(parts), "takenAt": .string(iso)]))
    }

    /// Allow-list, then the registry's own class check, then the call. Failure is a short reason code for the page.
    private func call(_ name: String, args: JSONValue) async -> Result<JSONValue, String> {
        guard Self.readAllowList.contains(name) else { return .failure("forbidden") }
        guard let capability = registry.capability(named: name), capability.kind == .read else { return .failure("forbidden") }
        let session = ArtifactSession(artifactID: nil, dryRun: false)
        switch await registry.call(name: name, args: args, session: session, granted: [name]) {
        case .success(let value): return .success(value)
        case .failure(.badArgs): return .failure("bad-args")
        case .failure(.rateLimited): return .failure("rate-limited")
        case .failure: return .failure("failed")
        }
    }

    private func reject(_ message: LinkMessage, reason: String) -> LinkMessage {
        LinkMessage(id: message.id, type: "reject", version: 1, payload: .object(["reason": .string(reason)]))
    }
}
