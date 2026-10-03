import XCTest
@testable import Palabra

final class SRSSchedulerTests: XCTestCase {
    private let scheduler = SRSScheduler()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func state(_ phase: SRSPhase, interval: Double = 0, ease: Double = 2.5, lapses: Int = 0) -> SRSState {
        SRSState(phase: phase, interval: interval, ease: ease, reps: 0, lapses: lapses, due: now)
    }

    func testNewAgainEntersLearningWithTenMinuteDelay() {
        let next = scheduler.next(state(.new), grade: .again, now: now)
        XCTAssertEqual(next.phase, .learning)
        XCTAssertEqual(next.due.timeIntervalSince(now), 600, accuracy: 0.001)
        XCTAssertEqual(next.lapses, 0)
    }

    func testNewHardStaysInLearning() {
        let next = scheduler.next(state(.new), grade: .hard, now: now)
        XCTAssertEqual(next.phase, .learning)
        XCTAssertEqual(next.due.timeIntervalSince(now), 1800, accuracy: 0.001)
    }

    func testNewGoodGraduatesToOneDay() {
        let next = scheduler.next(state(.new), grade: .good, now: now)
        XCTAssertEqual(next.phase, .review)
        XCTAssertEqual(next.interval, 1)
        XCTAssertEqual(next.due.timeIntervalSince(now), day, accuracy: 0.001)
        XCTAssertEqual(next.reps, 1)
    }

    func testNewEasyGraduatesToFourDaysAndRaisesEase() {
        let next = scheduler.next(state(.new), grade: .easy, now: now)
        XCTAssertEqual(next.phase, .review)
        XCTAssertEqual(next.interval, 4)
        XCTAssertEqual(next.ease, 2.65, accuracy: 0.0001)
    }

    func testReviewGoodMultipliesByEase() {
        let next = scheduler.next(state(.review, interval: 10), grade: .good, now: now)
        XCTAssertEqual(next.interval, 25)
        XCTAssertEqual(next.due.timeIntervalSince(now), 25 * day, accuracy: 0.001)
        XCTAssertEqual(next.ease, 2.5, accuracy: 0.0001)
    }

    func testReviewHardGrowsSlowlyAndLowersEase() {
        let next = scheduler.next(state(.review, interval: 10), grade: .hard, now: now)
        XCTAssertEqual(next.interval, 12)
        XCTAssertEqual(next.ease, 2.35, accuracy: 0.0001)
    }

    func testReviewEasyGrowsMostAndRaisesEase() {
        let next = scheduler.next(state(.review, interval: 10), grade: .easy, now: now)
        XCTAssertEqual(next.interval, 33)
        XCTAssertEqual(next.ease, 2.65, accuracy: 0.0001)
    }

    func testReviewAgainLapsesIntoRelearning() {
        let next = scheduler.next(state(.review, interval: 10), grade: .again, now: now)
        XCTAssertEqual(next.phase, .learning)
        XCTAssertEqual(next.lapses, 1)
        XCTAssertEqual(next.interval, 5)
        XCTAssertEqual(next.ease, 2.3, accuracy: 0.0001)
        XCTAssertEqual(next.due.timeIntervalSince(now), 600, accuracy: 0.001)
    }

    func testRelearningCardGraduatesToItsHalvedInterval() {
        let lapsed = scheduler.next(state(.review, interval: 10), grade: .again, now: now)
        let back = scheduler.next(lapsed, grade: .good, now: now)
        XCTAssertEqual(back.phase, .review)
        XCTAssertEqual(back.interval, 5)
    }

    func testEaseStaysWithinBounds() {
        let low = scheduler.next(state(.review, interval: 5, ease: 1.3), grade: .again, now: now)
        XCTAssertEqual(low.ease, 1.3, accuracy: 0.0001)
        let lowHard = scheduler.next(state(.review, interval: 5, ease: 1.3), grade: .hard, now: now)
        XCTAssertEqual(lowHard.ease, 1.3, accuracy: 0.0001)
        let high = scheduler.next(state(.review, interval: 5, ease: 3.0), grade: .easy, now: now)
        XCTAssertEqual(high.ease, 3.0, accuracy: 0.0001)
    }

    func testReviewIntervalsAreStrictlyOrderedHardGoodEasy() {
        for interval in [1.0, 2, 3, 10, 30, 100] {
            for ease in [1.3, 2.5, 3.0] {
                let s = state(.review, interval: interval, ease: ease)
                let hard = scheduler.next(s, grade: .hard, now: now).interval
                let good = scheduler.next(s, grade: .good, now: now).interval
                let easy = scheduler.next(s, grade: .easy, now: now).interval
                XCTAssertLessThan(hard, good, "interval \(interval) ease \(ease)")
                XCTAssertLessThan(good, easy, "interval \(interval) ease \(ease)")
            }
        }
    }

    func testIntervalIsCapped() {
        let next = scheduler.next(state(.review, interval: 3650), grade: .easy, now: now)
        XCTAssertEqual(next.interval, SRSScheduler.maxIntervalDays)
    }

    func testPreviewDelaysMatchNext() {
        let s = state(.review, interval: 10)
        let preview = scheduler.previewDelays(s, now: now)
        for grade in SRSGrade.allCases {
            XCTAssertEqual(preview[grade] ?? -1, scheduler.next(s, grade: grade, now: now).due.timeIntervalSince(now), accuracy: 0.001)
        }
    }
}
