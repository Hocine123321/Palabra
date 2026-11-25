import XCTest
@testable import Palabra

final class ReminderPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testBeforeTodaysTimeFiresToday() {
        let fire = ReminderPlanner.nextFire(after: date(24, 10), minutes: 19 * 60, calendar: calendar)
        XCTAssertEqual(fire, date(24, 19))
    }

    func testAfterTodaysTimeFiresTomorrow() {
        let fire = ReminderPlanner.nextFire(after: date(24, 20), minutes: 19 * 60, calendar: calendar)
        XCTAssertEqual(fire, date(25, 19))
    }

    func testExactlyAtTheTimeFiresTomorrow() {
        let fire = ReminderPlanner.nextFire(after: date(24, 19), minutes: 19 * 60, calendar: calendar)
        XCTAssertEqual(fire, date(25, 19))
    }

    func testMinutesPastTheHour() {
        let fire = ReminderPlanner.nextFire(after: date(24, 7), minutes: 8 * 60 + 30, calendar: calendar)
        XCTAssertEqual(fire, date(24, 8, 30))
    }

    func testOutOfRangeMinutesAreClamped() {
        XCTAssertEqual(ReminderPlanner.clampedMinutes(-5), 0)
        XCTAssertEqual(ReminderPlanner.clampedMinutes(5000), 24 * 60 - 1)
        XCTAssertEqual(ReminderPlanner.clampedMinutes(600), 600)
    }
}
