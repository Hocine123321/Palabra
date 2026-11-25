import Foundation
import UserNotifications

/// UserDefaults keys for the daily review reminder (the same keys `@AppStorage` uses in Settings).
enum ReminderKeys {
    static let enabled = "reminderEnabled"
    /// Minutes after midnight.
    static let minutes = "reminderMinutes"
    static let defaultMinutes = 19 * 60
}

enum ReminderPlanner {
    static func clampedMinutes(_ value: Int) -> Int { min(max(value, 0), 24 * 60 - 1) }

    /// The next moment after `now` when the clock reads `minutes` past midnight.
    static func nextFire(after now: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let minutes = clampedMinutes(minutes)
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }
}

/// One local notification at the person's chosen time, only when cards will be waiting. Local notifications need
/// no server and no entitlement, so they work in a sideloaded build.
@MainActor
enum ReminderScheduler {
    static let identifier = "dailyReview"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces the pending reminder with one for the next reminder time, counting what will be waiting then.
    /// It is a single notification, not a repeat: it is planned again every time the app goes to the background, so
    /// the number is fresh and someone who stops studying gets one nudge, not a daily one.
    static func reschedule(environment: AppEnvironment, defaults: UserDefaults = .standard, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard defaults.bool(forKey: ReminderKeys.enabled) else { return }
        let minutes = (defaults.object(forKey: ReminderKeys.minutes) as? Int) ?? ReminderKeys.defaultMinutes
        let fire = ReminderPlanner.nextFire(after: now, minutes: minutes)
        let counts = environment.cards.counts(now: fire)
        let waiting = DeckCounts.totalDue(counts)
            + min(counts.values.reduce(0) { $0 + $1.new }, environment.newCardsPerDay)
        guard waiting > 0 else { return }

        let language = environment.appLanguage
        let content = UNMutableNotificationContent()
        content.title = localized("Time to review", language)
        content.body = waiting == 1
            ? localized("1 card is waiting for you", language)
            : String(format: localized("%lld cards are waiting for you", language), waiting)
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// The app's own language (not the phone's): notifications are made outside SwiftUI, so they look the text up here.
    private static func localized(_ key: String, _ language: SupportedLanguage) -> String {
        guard language == .arabic,
              let path = Bundle.main.path(forResource: "ar", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
