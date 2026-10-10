import XCTest
@testable import Palabra

final class StudyStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2026-10-10 15:00 UTC
    private let now = Date(timeIntervalSince1970: 1_791_644_400)

    private func ago(days: Int, hours: Int = 0) -> Date {
        calendar.date(byAdding: .hour, value: -hours, to: calendar.date(byAdding: .day, value: -days, to: now)!)!
    }

    private func stats(_ dates: [Date]) -> StudyStats {
        StudyStatsCalculator.stats(reviewDates: dates, now: now, calendar: calendar)
    }

    func testNoHistory() {
        XCTAssertEqual(stats([]), StudyStats())
    }

    func testTodayCountsAndStartsAStreak() {
        let s = stats([ago(days: 0), ago(days: 0, hours: 5)])
        XCTAssertEqual(s.reviewedToday, 2)
        XCTAssertEqual(s.streak, 1)
        XCTAssertEqual(s.lastSevenDays, [0, 0, 0, 0, 0, 0, 2])
    }

    func testStreakCountsConsecutiveDays() {
        let s = stats([ago(days: 0), ago(days: 1), ago(days: 2), ago(days: 4)])
        XCTAssertEqual(s.streak, 3)
        XCTAssertEqual(s.lastSevenDays, [0, 0, 1, 0, 1, 1, 1])
    }

    func testStreakSurvivesAnEmptyToday() {
        let s = stats([ago(days: 1), ago(days: 2)])
        XCTAssertEqual(s.reviewedToday, 0)
        XCTAssertEqual(s.streak, 2)
    }

    func testAGapOfADayEndsTheStreak() {
        XCTAssertEqual(stats([ago(days: 2), ago(days: 3)]).streak, 0)
    }

    func testFutureDatesAreIgnoredAndOldOnesOnlyCountForTheStreak() {
        let future = calendar.date(byAdding: .day, value: 2, to: now)!
        let s = stats([future, ago(days: 30)])
        XCTAssertEqual(s.reviewedToday, 0)
        XCTAssertEqual(s.streak, 0)
        XCTAssertEqual(s.lastSevenDays, Array(repeating: 0, count: 7))
    }

    func testLongStreakPastTheWeekWindow() {
        let s = stats((0..<12).map { ago(days: $0) })
        XCTAssertEqual(s.streak, 12)
        XCTAssertEqual(s.lastSevenDays, Array(repeating: 1, count: 7))
    }
}
