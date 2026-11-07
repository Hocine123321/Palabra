import XCTest
@testable import Palabra

final class ReconnectBackoffTests: XCTestCase {
    func testWaitsGrowThenStopAtFifteenSeconds() {
        var backoff = ReconnectBackoff()
        var waits: [TimeInterval] = []
        for _ in 0..<8 { waits.append(backoff.next()) }
        XCTAssertEqual(waits, [1, 2, 4, 8, 15, 15, 15, 15])
    }

    func testAWorkingConnectionStartsOverFromTheShortWait() {
        var backoff = ReconnectBackoff()
        _ = backoff.next(); _ = backoff.next(); _ = backoff.next()
        backoff.reset()
        XCTAssertEqual(backoff.next(), 1)
    }

    func testItNeverOverflowsAfterManyFailures() {
        var backoff = ReconnectBackoff()
        var last: TimeInterval = 0
        for _ in 0..<5_000 { last = backoff.next() }
        XCTAssertEqual(last, ReconnectBackoff.cap)
    }
}
