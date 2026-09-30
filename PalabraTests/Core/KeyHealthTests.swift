import XCTest
@testable import Palabra

final class KeyHealthTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPrimaryIsUsedWhileHealthy() {
        let health = KeyHealth()
        XCTAssertEqual(health.slotToUse(hasFallback: true, now: t0), .primary)
    }

    func testQuotaBenchesPrimaryForAnHourThenItReturns() {
        var health = KeyHealth()
        XCTAssertTrue(health.recordFailure(.primary, error: .quotaExhausted, now: t0))
        XCTAssertEqual(health.slotToUse(hasFallback: true, now: t0.addingTimeInterval(10)), .fallback)
        XCTAssertNil(health.slotToUse(hasFallback: false, now: t0.addingTimeInterval(10)), "no backup: nothing to use")
        XCTAssertEqual(health.slotToUse(hasFallback: true, now: t0.addingTimeInterval(3601)), .primary, "primary is preferred again once it recovers")
    }

    func testRateLimitIsBenchedBriefly() {
        var health = KeyHealth()
        health.recordFailure(.primary, error: .rateLimited, now: t0)
        XCTAssertEqual(health.reason(.primary), .rateLimited)
        XCTAssertTrue(health.isBenched(.primary, now: t0.addingTimeInterval(30)))
        XCTAssertFalse(health.isBenched(.primary, now: t0.addingTimeInterval(61)))
    }

    func testSingleServerBlipDoesNotBenchButARunOfThemDoes() {
        var health = KeyHealth()
        XCTAssertFalse(health.recordFailure(.primary, error: .serverError(500), now: t0))
        XCTAssertFalse(health.recordFailure(.primary, error: .timeout, now: t0))
        XCTAssertTrue(health.recordFailure(.primary, error: .serverError(503), now: t0))
        XCTAssertEqual(health.reason(.primary), .flaky)
    }

    func testSuccessClearsTheFailureRun() {
        var health = KeyHealth()
        health.recordFailure(.primary, error: .serverError(500), now: t0)
        health.recordFailure(.primary, error: .serverError(500), now: t0)
        health.recordSuccess(.primary)
        XCTAssertFalse(health.recordFailure(.primary, error: .serverError(500), now: t0), "the run started over")
    }

    func testErrorsThatAreNotTheKeysFaultNeverBenchIt() {
        var health = KeyHealth()
        for error in [AIError.offline, .malformedResponse, .blocked("x"), .truncated] {
            XCTAssertFalse(health.recordFailure(.primary, error: error, now: t0), "\(error)")
        }
    }

    func testReplacingAKeyForgetsItsHistory() {
        var health = KeyHealth()
        health.recordFailure(.primary, error: .invalidAPIKey, now: t0)
        XCTAssertTrue(health.isBenched(.primary, now: t0))
        health.reset(.primary)
        XCTAssertFalse(health.isBenched(.primary, now: t0))
        XCTAssertNil(health.reason(.primary))
    }

    func testBothBenchedMeansNothingToUse() {
        var health = KeyHealth()
        health.recordFailure(.primary, error: .quotaExhausted, now: t0)
        health.recordFailure(.fallback, error: .quotaExhausted, now: t0)
        XCTAssertNil(health.slotToUse(hasFallback: true, now: t0.addingTimeInterval(5)))
    }
}
