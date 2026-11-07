import Foundation

/// How long the phone waits before trying the relay again: 1, 2, 4, 8 seconds, then every 15.
/// Pure and tiny so it can be tested; the controller owns the timer.
struct ReconnectBackoff: Equatable, Sendable {
    static let cap: TimeInterval = 15
    private(set) var attempt = 0

    /// The wait before the next try, then counts that try.
    mutating func next() -> TimeInterval {
        let wait = min(Self.cap, pow(2, Double(attempt)))
        attempt += 1
        return wait
    }

    /// A connection worked: start from the short wait again.
    mutating func reset() { attempt = 0 }
}
