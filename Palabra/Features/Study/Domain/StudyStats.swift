import Foundation

/// How much the person studied lately. Plain values; computed from review timestamps only.
struct StudyStats: Equatable {
    /// Answers given today.
    var reviewedToday = 0
    /// Consecutive days with at least one answer, ending today (or yesterday while today is still empty).
    var streak = 0
    /// Answers per day for the last seven days, oldest first; the last entry is today.
    var lastSevenDays: [Int] = Array(repeating: 0, count: 7)
}

enum StudyStatsCalculator {
    static func stats(reviewDates: [Date], now: Date, calendar: Calendar = .current) -> StudyStats {
        let today = calendar.startOfDay(for: now)
        var perDay: [Date: Int] = [:]
        for date in reviewDates {
            let day = calendar.startOfDay(for: date)
            if day <= today { perDay[day, default: 0] += 1 }
        }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today) ?? today }

        var stats = StudyStats()
        stats.reviewedToday = perDay[today] ?? 0
        stats.lastSevenDays = (0..<7).reversed().map { perDay[day($0)] ?? 0 }
        var offset = perDay[today] == nil ? 1 : 0
        while perDay[day(offset)] != nil {
            stats.streak += 1
            offset += 1
        }
        return stats
    }
}
