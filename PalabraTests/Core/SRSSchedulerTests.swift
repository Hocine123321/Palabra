import XCTest
@testable import Palabra

final class SRSSchedulerTests: XCTestCase {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let scheduler = SRSScheduler(calendar: SRSSchedulerTests.utc)
    /// 2027-01-15 08:00 UTC. That study day began at 04:00 UTC the same morning (1_799_985_600).
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let studyDayStart = Date(timeIntervalSince1970: 1_799_985_600)
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
        XCTAssertEqual(next.due.timeIntervalSince(studyDayStart), day, accuracy: 0.001, "due at the start of the next study day")
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
        XCTAssertEqual(next.due.timeIntervalSince(studyDayStart), 25 * day, accuracy: 0.001)
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

    func testAStudyDayStartsAtFourInTheMorning() {
        func at(_ hour: Int, day: Int) -> Date {
            SRSSchedulerTests.utc.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour))!
        }
        // 21:00 on the 14th and 02:00 on the 15th are the same study day (it began at 04:00 on the 14th).
        let began = at(4, day: 14)
        XCTAssertEqual(SRSScheduler.studyDayStart(for: at(21, day: 14), calendar: SRSSchedulerTests.utc), began)
        XCTAssertEqual(SRSScheduler.studyDayStart(for: at(2, day: 15), calendar: SRSSchedulerTests.utc), began)
        XCTAssertEqual(SRSScheduler.studyDayStart(for: at(4, day: 15), calendar: SRSSchedulerTests.utc), at(4, day: 15))
    }

    func testACardAnsweredLateInTheEveningIsDueFirstThingNextMorning() {
        let evening = SRSSchedulerTests.utc.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 21))!
        let next = scheduler.next(state(.new), grade: .good, now: evening)
        XCTAssertEqual(next.due, SRSSchedulerTests.utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 4)))
        // The old "now + 24 h" rule would have made it wait until 21:00.
        XCTAssertLessThan(next.due.timeIntervalSince(evening), day)
    }

    func testDueTimeStaysAtFourAcrossAClockChange() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduler = SRSScheduler(calendar: newYork)
        // 2027-03-13 20:00 New York; the clocks change that night.
        let before = newYork.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 20))!
        let next = scheduler.next(state(.new), grade: .good, now: before)
        XCTAssertEqual(newYork.dateComponents([.month, .day, .hour], from: next.due), DateComponents(month: 3, day: 14, hour: 4))
    }

    func testPreviewDelaysMatchNext() {
        let s = state(.review, interval: 10)
        let preview = scheduler.previewDelays(s, now: now)
        for grade in SRSGrade.allCases {
            XCTAssertEqual(preview[grade] ?? -1, scheduler.next(s, grade: grade, now: now).due.timeIntervalSince(now), accuracy: 0.001)
        }
    }
}
