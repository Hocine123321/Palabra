import XCTest
@testable import Palabra

final class SpacedRepetitionTests: XCTestCase {
    func testNewCardStartsAtZeroRepetitionsAndDueNow() {
        let now = Date()
        let state = SpacedRepetition.State.new(now: now)
        XCTAssertEqual(state.repetitions, 0)
        XCTAssertEqual(state.intervalDays, 0)
        XCTAssertEqual(state.easeFactor, 2.5)
        XCTAssertEqual(state.dueDate, now)
    }

    func testFirstGoodReviewSchedulesOneDayOut() {
        let now = Date()
        let state = SpacedRepetition.State.new(now: now)
        let next = SpacedRepetition.schedule(state, grade: .good, now: now)
        XCTAssertEqual(next.repetitions, 1)
        XCTAssertEqual(next.intervalDays, 1, accuracy: 0.001)
        XCTAssertEqual(next.dueDate.timeIntervalSince(now), 86400, accuracy: 1)
    }

    func testFirstEasyReviewSchedulesFurtherThanGood() {
        let now = Date()
        let state = SpacedRepetition.State.new(now: now)
        let good = SpacedRepetition.schedule(state, grade: .good, now: now)
        let easy = SpacedRepetition.schedule(state, grade: .easy, now: now)
        XCTAssertGreaterThan(easy.intervalDays, good.intervalDays)
    }

    func testAgainResetsRepetitionsAndSchedulesSoon() {
        let now = Date()
        var state = SpacedRepetition.State.new(now: now)
        state = SpacedRepetition.schedule(state, grade: .good, now: now)
        state = SpacedRepetition.schedule(state, grade: .good, now: now)
        XCTAssertGreaterThan(state.repetitions, 0)

        let lapsed = SpacedRepetition.schedule(state, grade: .again, now: now)
        XCTAssertEqual(lapsed.repetitions, 0)
        XCTAssertLessThan(lapsed.intervalDays, 1)
        XCTAssertLessThan(lapsed.easeFactor, state.easeFactor)
    }

    func testEaseFactorNeverDropsBelowMinimum() {
        let now = Date()
        var state = SpacedRepetition.State.new(now: now)
        for _ in 0..<20 {
            state = SpacedRepetition.schedule(state, grade: .again, now: now)
        }
        XCTAssertGreaterThanOrEqual(state.easeFactor, SpacedRepetition.minEaseFactor)
        XCTAssertEqual(state.easeFactor, SpacedRepetition.minEaseFactor, accuracy: 0.001)
    }

    func testIntervalGrowsAcrossRepeatedGoodReviewsAndCapsAtMaximum() {
        let now = Date()
        var state = SpacedRepetition.State.new(now: now)
        var previousInterval = -1.0
        for _ in 0..<10 {
            state = SpacedRepetition.schedule(state, grade: .good, now: now)
            XCTAssertGreaterThanOrEqual(state.intervalDays, previousInterval)
            previousInterval = state.intervalDays
        }
        XCTAssertLessThanOrEqual(state.intervalDays, SpacedRepetition.maxIntervalDays)
    }

    func testHardReviewGrowsIntervalLessThanGood() {
        let now = Date()
        var goodState = SpacedRepetition.State.new(now: now)
        var hardState = goodState
        for _ in 0..<3 {
            goodState = SpacedRepetition.schedule(goodState, grade: .good, now: now)
            hardState = SpacedRepetition.schedule(hardState, grade: .hard, now: now)
        }
        XCTAssertLessThan(hardState.intervalDays, goodState.intervalDays)
    }
}
