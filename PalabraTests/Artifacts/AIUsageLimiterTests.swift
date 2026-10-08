import XCTest
@testable import Palabra

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date = date.addingTimeInterval(seconds); lock.unlock() }
}

final class AIUsageLimiterTests: XCTestCase {
    private let clock = TestClock()
    private func makeLimiter() -> AIUsageLimiter {
        let clock = self.clock
        return AIUsageLimiter(now: { clock.now })
    }

    func testTenCallsPassThenTheEleventhIsDenied() {
        let limiter = makeLimiter()
        let id = UUID()
        for _ in 0..<10 { XCTAssertTrue(limiter.allow(sessionID: id)) }
        XCTAssertFalse(limiter.allow(sessionID: id))
    }

    func testWindowRollsAfterAMinute() {
        let limiter = makeLimiter()
        let id = UUID()
        for _ in 0..<10 { _ = limiter.allow(sessionID: id) }
        XCTAssertFalse(limiter.allow(sessionID: id))
        clock.advance(61)
        XCTAssertTrue(limiter.allow(sessionID: id))
    }

    func testHundredthPlusOneIsDeniedAcrossMinutes() {
        let limiter = makeLimiter()
        let id = UUID()
        for _ in 0..<100 {
            XCTAssertTrue(limiter.allow(sessionID: id))
            clock.advance(7) // never more than 9 in a window, so only the total can stop it
        }
        XCTAssertFalse(limiter.allow(sessionID: id))
    }

    func testSessionsAreIndependent() {
        let limiter = makeLimiter()
        let first = UUID()
        let second = UUID()
        for _ in 0..<10 { _ = limiter.allow(sessionID: first) }
        XCTAssertFalse(limiter.allow(sessionID: first))
        XCTAssertTrue(limiter.allow(sessionID: second))
    }

    func testEndForgetsASession() {
        let limiter = makeLimiter()
        let id = UUID()
        for _ in 0..<10 { _ = limiter.allow(sessionID: id) }
        limiter.end(sessionID: id)
        XCTAssertTrue(limiter.allow(sessionID: id))
    }

    func testOldestSessionsAreForgottenBeyondSixtyFour() {
        let limiter = makeLimiter()
        let first = UUID()
        for _ in 0..<10 { _ = limiter.allow(sessionID: first) }
        for _ in 0..<64 { _ = limiter.allow(sessionID: UUID()) }
        XCTAssertTrue(limiter.allow(sessionID: first)) // its history was dropped
    }
}
