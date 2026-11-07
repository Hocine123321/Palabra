import Foundation

/// Counts wrong pairing codes and decides when pairing is locked. Pure: the caller supplies the clock and
/// stores the value, so the count survives the page reloading (it lives in the app, not the page).
/// 5 wrong tries lock pairing out for 30 s, then 2 min, then 10 min, then 1 h (the cap) for every repeat.
struct PairingLockout: Codable, Equatable, Sendable {
    static let triesBeforeLockout = 5
    static let durations: [TimeInterval] = [30, 120, 600, 3600]

    private(set) var wrongInRow = 0
    /// How many lockouts have happened since the last successful pairing.
    private(set) var lockoutsSoFar = 0
    private(set) var lockedUntil: Date?

    func remaining(now: Date) -> TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSince(now))
    }

    func isLocked(now: Date) -> Bool { remaining(now: now) > 0 }

    /// Records a wrong code. Returns the lockout that started, if this was the fifth.
    @discardableResult
    mutating func recordWrong(now: Date) -> TimeInterval? {
        wrongInRow += 1
        guard wrongInRow >= Self.triesBeforeLockout else { return nil }
        let length = Self.durations[min(lockoutsSoFar, Self.durations.count - 1)]
        lockoutsSoFar += 1
        wrongInRow = 0
        lockedUntil = now.addingTimeInterval(length)
        return length
    }

    /// A right code clears the count and the growth.
    mutating func recordSuccess() { self = PairingLockout() }
}
