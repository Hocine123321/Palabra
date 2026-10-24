import Foundation

enum SRSGrade: Int, CaseIterable, Sendable {
    case again = 0, hard = 1, good = 2, easy = 3
}

enum SRSPhase: String, Sendable {
    case new, learning, review
}

/// Everything the scheduler needs to know about one card. Intervals are in days.
/// For a `.learning` card, `interval` is the interval it graduates to (0 = first time).
struct SRSState: Equatable, Sendable {
    var phase: SRSPhase
    var interval: Double
    var ease: Double
    var reps: Int
    var lapses: Int
    var due: Date

    static func fresh(due: Date) -> SRSState {
        SRSState(phase: .new, interval: 0, ease: SRSScheduler.startingEase, reps: 0, lapses: 0, due: due)
    }
}

/// SM-2-style spaced repetition. Pure: no UI, no storage, `now` is passed in.
struct SRSScheduler: Sendable {
    static let startingEase = 2.5
    static let minEase = 1.3
    static let maxEase = 3.0
    static let maxIntervalDays = 3650.0
    static let againDelay: TimeInterval = 10 * 60
    static let hardLearningDelay: TimeInterval = 30 * 60
    /// A study day starts at 04:00 local time, not midnight (as in Anki): someone who studies after midnight is still on
    /// the same day, and a card answered at any hour of a day is due at the start of a later study day.
    static let rolloverHour = 4

    /// Whole-day intervals are counted in study days of this calendar (device calendar and time zone by default).
    let calendar: Calendar

    init(calendar: Calendar = .current) { self.calendar = calendar }

    /// When the study day containing `date` began.
    static func studyDayStart(for date: Date, calendar: Calendar = .current) -> Date {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let midnight = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: rolloverHour, to: midnight) ?? midnight.addingTimeInterval(Double(rolloverHour) * 3600)
    }

    /// The start of the study day `days` after the one `now` belongs to.
    func dueDate(afterDays days: Double, from now: Date) -> Date {
        let start = Self.studyDayStart(for: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: Int(days), to: start) ?? start.addingTimeInterval(days * 86_400)
    }

    func next(_ state: SRSState, grade: SRSGrade, now: Date) -> SRSState {
        var n = state
        switch state.phase {
        case .new, .learning:
            switch grade {
            case .again:
                n.phase = .learning
                n.due = now.addingTimeInterval(Self.againDelay)
            case .hard:
                n.phase = .learning
                n.due = now.addingTimeInterval(Self.hardLearningDelay)
            case .good:
                n.reps += 1
                graduate(&n, days: max(1, state.interval), now: now)
            case .easy:
                n.reps += 1
                n.ease = min(Self.maxEase, state.ease + 0.15)
                graduate(&n, days: max(4, state.interval * 1.3), now: now)
            }
        case .review:
            switch grade {
            case .again:
                n.phase = .learning
                n.lapses += 1
                n.ease = max(Self.minEase, state.ease - 0.2)
                n.interval = max(1, (state.interval * 0.5).rounded())
                n.due = now.addingTimeInterval(Self.againDelay)
            case .hard:
                n.reps += 1
                n.ease = max(Self.minEase, state.ease - 0.15)
                graduate(&n, days: hardInterval(state), now: now)
            case .good:
                n.reps += 1
                graduate(&n, days: goodInterval(state), now: now)
            case .easy:
                n.reps += 1
                n.ease = min(Self.maxEase, state.ease + 0.15)
                graduate(&n, days: max(goodInterval(state) + 1, (state.interval * state.ease * 1.3).rounded()), now: now)
            }
        }
        return n
    }

    /// Seconds until due for each grade, used for the labels on the grade buttons.
    func previewDelays(_ state: SRSState, now: Date) -> [SRSGrade: TimeInterval] {
        var result: [SRSGrade: TimeInterval] = [:]
        for grade in SRSGrade.allCases {
            result[grade] = next(state, grade: grade, now: now).due.timeIntervalSince(now)
        }
        return result
    }

    // Ordering invariant for review cards: hard < good < easy (strictly, below the cap).
    private func hardInterval(_ s: SRSState) -> Double { max(1, (s.interval * 1.2).rounded()) }
    private func goodInterval(_ s: SRSState) -> Double { max(hardInterval(s) + 1, (s.interval * s.ease).rounded()) }

    private func graduate(_ n: inout SRSState, days: Double, now: Date) {
        n.phase = .review
        n.interval = min(Self.maxIntervalDays, days.rounded())
        n.due = dueDate(afterDays: n.interval, from: now)
    }
}
