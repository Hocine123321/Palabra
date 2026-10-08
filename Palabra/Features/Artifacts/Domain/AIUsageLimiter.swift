import Foundation

/// Limits `ai.generate` per open artifact session: `perMinute` calls in any rolling 60 seconds and
/// `total` calls overall. Thread-safe; tracks at most 64 sessions (the oldest are forgotten).
final class AIUsageLimiter: @unchecked Sendable {
    private struct Usage {
        var recent: [Date] = []
        var total = 0
    }

    private static let maxSessions = 64
    private let perMinute: Int
    private let total: Int
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var sessions: [UUID: Usage] = [:]
    private var order: [UUID] = []

    init(perMinute: Int = 10, total: Int = 100, now: @escaping @Sendable () -> Date = { Date() }) {
        self.perMinute = perMinute
        self.total = total
        self.now = now
    }

    /// Records a call and returns true if it is allowed.
    func allow(sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let date = now()
        var usage = sessions[sessionID] ?? Usage()
        if sessions[sessionID] == nil { order.append(sessionID) }
        usage.recent.removeAll { date.timeIntervalSince($0) >= 60 }
        let allowed = usage.total < total && usage.recent.count < perMinute
        if allowed {
            usage.recent.append(date)
            usage.total += 1
        }
        sessions[sessionID] = usage
        while order.count > Self.maxSessions {
            sessions[order.removeFirst()] = nil
        }
        return allowed
    }

    /// Forgets a session (its screen closed).
    func end(sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sessions[sessionID] = nil
        order.removeAll { $0 == sessionID }
    }
}
