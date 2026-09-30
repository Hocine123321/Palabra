import Foundation

/// Tracks which of the (up to two) API keys is currently trusted, so a key that just
/// failed for a reason a retry can't fix is not hammered again on every call.
///
/// Pure value logic driven by an injected clock, so it can be tested without waiting.
struct KeyHealth: Equatable, Sendable {
    enum Slot: String, Codable, Sendable { case primary, fallback }

    /// Why a key was benched, which decides how long for.
    enum Reason: Equatable, Sendable {
        case rateLimited
        case quotaExhausted
        case rejected      // invalid key or permission denied
        case flaky         // repeated server/timeout failures
    }

    private(set) var benchedUntil: [Slot: Date] = [:]
    private(set) var reasons: [Slot: Reason] = [:]
    private(set) var consecutiveFailures: [Slot: Int] = [:]
    /// Which slot the app is currently using.
    private(set) var active: Slot = .primary

    /// How long a key stays benched. A per-minute limit clears fast; a daily quota
    /// won't clear for hours; a rejected key stays out until the user changes it.
    static func benchDuration(_ reason: Reason) -> TimeInterval {
        switch reason {
        case .rateLimited: return 60
        case .flaky: return 120
        case .quotaExhausted: return 60 * 60
        case .rejected: return 24 * 60 * 60
        }
    }

    func isBenched(_ slot: Slot, now: Date) -> Bool {
        guard let until = benchedUntil[slot] else { return false }
        return until > now
    }

    func reason(_ slot: Slot) -> Reason? { reasons[slot] }

    /// The slot a call should use right now, preferring the primary key as soon as it
    /// recovers. Returns nil when both are benched (the caller then asks the user).
    func slotToUse(hasFallback: Bool, now: Date) -> Slot? {
        if !isBenched(.primary, now: now) { return .primary }
        if hasFallback, !isBenched(.fallback, now: now) { return .fallback }
        return nil
    }

    mutating func recordSuccess(_ slot: Slot) {
        consecutiveFailures[slot] = 0
        benchedUntil[slot] = nil
        reasons[slot] = nil
        active = slot
    }

    /// Records a failure; returns true if the key was benched as a result.
    @discardableResult
    mutating func recordFailure(_ slot: Slot, error: AIError, now: Date) -> Bool {
        consecutiveFailures[slot, default: 0] += 1
        let reason: Reason?
        switch error {
        case .invalidAPIKey, .permissionDenied: reason = .rejected
        case .quotaExhausted: reason = .quotaExhausted
        case .rateLimited: reason = .rateLimited
        case .serverError, .timeout:
            // One blip is not a reason to switch; a run of them is.
            reason = consecutiveFailures[slot, default: 0] >= 3 ? .flaky : nil
        default: reason = nil
        }
        guard let reason else { return false }
        benchedUntil[slot] = now.addingTimeInterval(Self.benchDuration(reason))
        reasons[slot] = reason
        return true
    }

    /// The user replaced a key: forget everything we knew about that slot.
    mutating func reset(_ slot: Slot) {
        benchedUntil[slot] = nil
        reasons[slot] = nil
        consecutiveFailures[slot] = 0
        if slot == .primary { active = .primary }
    }
}
