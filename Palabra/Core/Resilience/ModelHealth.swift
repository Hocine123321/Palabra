import Foundation

/// What the app currently believes about one model, as shown next to it in the model lists.
enum ModelStatus: Equatable, Sendable {
    /// Nothing recent: never used, or last used long ago.
    case unknown
    /// Answered recently and nothing has gone wrong since.
    case working
    /// Over the per-minute limit. Clears by itself within a minute or so.
    case rateLimited
    /// Its daily or billing quota is used up.
    case quotaUsed
    /// Google's servers are struggling with it right now.
    case unstable
    /// Google says it doesn't exist (any more) for this key.
    case unavailable

    /// Worth trying: nothing known against it.
    var isUsable: Bool { self == .unknown || self == .working }
}

/// One model's record: when it last answered, and the last thing that went wrong with it.
struct ModelHealth: Codable, Equatable, Sendable {
    enum Problem: String, Codable, Sendable { case rateLimited, quotaUsed, unavailable, serverTrouble }

    var lastSuccess: Date?
    var problem: Problem?
    var problemAt: Date?
    /// Until when the problem is assumed to last. After that the model is tried again.
    var problemUntil: Date?

    /// A "working" mark fades after this long without a fresh success, since limits and outages change.
    static let workingLifetime: TimeInterval = 6 * 3600
    static let rateLimitPause: TimeInterval = 60
    static let quotaPause: TimeInterval = 3600
    static let serverPause: TimeInterval = 120
    static let unavailablePause: TimeInterval = 24 * 3600
    /// Records older than this are dropped when loading.
    static let retention: TimeInterval = 7 * 24 * 3600

    func status(at now: Date) -> ModelStatus {
        if let problem, let until = problemUntil, until > now {
            switch problem {
            case .rateLimited: return .rateLimited
            case .quotaUsed: return .quotaUsed
            case .unavailable: return .unavailable
            case .serverTrouble: return .unstable
            }
        }
        // A problem that has run its course says "try again", not "works": only a fresh success marks a model working.
        if problem != nil { return .unknown }
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < Self.workingLifetime { return .working }
        return .unknown
    }

    /// A success this soon after the last one changes nothing worth saving or redrawing.
    static let successRefresh: TimeInterval = 30

    mutating func recordSuccess(at now: Date) {
        if problem == nil, let lastSuccess, now.timeIntervalSince(lastSuccess) < Self.successRefresh, now >= lastSuccess { return }
        lastSuccess = now
        problem = nil
        problemAt = nil
        problemUntil = nil
    }

    /// Returns false when the error says nothing about the model (offline, a bad key, a blocked prompt).
    @discardableResult
    mutating func recordFailure(_ error: AIError, at now: Date) -> Bool {
        let found: (Problem, TimeInterval)
        switch error {
        case .rateLimited: found = (.rateLimited, Self.rateLimitPause)
        case .quotaExhausted: found = (.quotaUsed, Self.quotaPause)
        case .modelUnavailable: found = (.unavailable, Self.unavailablePause)
        case .serverError, .timeout: found = (.serverTrouble, Self.serverPause)
        default: return false
        }
        problem = found.0
        problemAt = now
        problemUntil = now.addingTimeInterval(found.1)
        return true
    }
}

/// Learns which models work, from every real request and from the "Test" button, and remembers it across launches.
/// Thread-safe: `ResilientAIClient` writes from background tasks while the model lists read on the main thread.
final class ModelHealthStore: @unchecked Sendable {
    static let defaultsKey = "modelHealth"

    private let lock = NSLock()
    private var entries: [String: ModelHealth]
    private let defaults: UserDefaults?
    private var changeHandler: (@Sendable () -> Void)?

    /// Pass `defaults` to persist; without it the store lives only as long as the app run (tests, previews).
    init(defaults: UserDefaults? = nil, now: Date = Date()) {
        self.defaults = defaults
        if let defaults, let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: ModelHealth].self, from: data) {
            entries = saved.filter { _, health in
                let newest = max(health.lastSuccess ?? .distantPast, health.problemAt ?? .distantPast)
                return now.timeIntervalSince(newest) < ModelHealth.retention
            }
        } else {
            entries = [:]
        }
    }

    /// Called (on whatever thread recorded the change) after every change, so the UI can refresh.
    func onChange(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func status(for id: String, now: Date = Date()) -> ModelStatus {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.status(at: now) ?? .unknown
    }

    func recordSuccess(_ id: String, now: Date = Date()) {
        mutate { $0[id, default: ModelHealth()].recordSuccess(at: now) }
    }

    func recordFailure(_ id: String, error: AIError, now: Date = Date()) {
        mutate { entries in
            var health = entries[id] ?? ModelHealth()
            if health.recordFailure(error, at: now) { entries[id] = health }
        }
    }

    func reset() {
        mutate { $0 = [:] }
    }

    private func mutate(_ change: (inout [String: ModelHealth]) -> Void) {
        lock.lock()
        let before = entries
        change(&entries)
        let after = entries
        let handler = changeHandler
        lock.unlock()
        guard after != before else { return }
        if let defaults, let data = try? JSONEncoder().encode(after) { defaults.set(data, forKey: Self.defaultsKey) }
        handler?()
    }
}

/// Picks which model to use instead when the chosen one is busy, over its quota, or gone.
enum BackupModelPicker {
    /// Models to try next, best first. Never the failed one, never one already known to be limited or missing.
    /// Order: the model the person chose as their backup, then models that answered recently, then the rest
    /// (fast "flash" models before "lite" ones before the heavier kind, which free keys often can't use; stable before preview).
    static func candidates(
        failed: AIModel,
        models: [AIModel],
        health: ModelHealthStore,
        preferredID: String?,
        now: Date = Date()
    ) -> [AIModel] {
        let pool = models.enumerated().filter { _, model in
            model.id != failed.id && health.status(for: model.id, now: now).isUsable
        }
        func rank(_ item: (offset: Int, element: AIModel)) -> [Int] {
            let model = item.element
            if let preferredID, model.id == preferredID { return [0, 0, 0, item.offset] }
            if health.status(for: model.id, now: now) == .working { return [1, 0, 0, item.offset] }
            return [2, tier(of: model), isExperimental(model) ? 1 : 0, item.offset]
        }
        return pool.sorted { rank($0).lexicographicallyPrecedes(rank($1)) }.map(\.element)
    }

    /// Preview and experimental builds come after stable ones of the same kind.
    private static func isExperimental(_ model: AIModel) -> Bool {
        let id = model.id.lowercased()
        return id.contains("preview") || id.contains("exp")
    }

    private static func tier(of model: AIModel) -> Int {
        let id = model.id.lowercased()
        if id.contains("flash") { return id.contains("lite") ? 1 : 0 }
        return 2
    }
}

/// A tiny real request, to find out whether a model answers right now.
enum ModelProbe {
    static let prompt = "Reply with the single word: ok"
    static let instruction = "You are a connectivity check. Answer with one word."

    /// Records the outcome in `health`. Uses one attempt on the main key: no retries, no backup key, no questions.
    @discardableResult
    static func test(
        _ model: AIModel,
        apiKey: String,
        using client: AIClient,
        health: ModelHealthStore,
        now: Date = Date()
    ) async -> Result<Void, AIError> {
        let result = await client.generateJSON(
            prompt: prompt,
            systemInstruction: instruction,
            schema: nil,
            apiKey: apiKey,
            model: model,
            temperature: 0
        )
        switch result {
        case .success:
            health.recordSuccess(model.id, now: now)
            return .success(())
        case .failure(let error):
            health.recordFailure(model.id, error: error, now: now)
            return .failure(error)
        }
    }

    /// True when the failure says nothing about this model, so testing the others would fail the same way.
    static func shouldStop(after error: AIError) -> Bool {
        switch error {
        case .offline, .invalidAPIKey, .permissionDenied, .missingAPIKey, .noModelSelected: return true
        default: return false
        }
    }
}
