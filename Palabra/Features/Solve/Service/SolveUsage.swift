import Foundation

/// A local tally of Wolfram|Alpha calls this month, to keep the free allowance (2,000 non-commercial calls)
/// visible. It is an estimate: Wolfram keeps the real count.
struct SolveUsage {
    static let freeMonthlyCalls = 2_000

    private struct Stored: Codable {
        var month: String
        var count: Int
    }

    private let defaults: UserDefaults
    private let key = "wolframUsage"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func count(now: Date) -> Int {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.month == Self.month(of: now) else { return 0 }
        return stored.count
    }

    func record(now: Date) {
        let stored = Stored(month: Self.month(of: now), count: count(now: now) + 1)
        defaults.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    /// "2026-10", in UTC so the tally does not depend on the device's time zone.
    static func month(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
