import Foundation

/// Pure SM-2-style spaced-repetition scheduler. No I/O and no persistence —
/// it takes a card's current review `State` and a recall `Grade` and returns
/// the next `State`. `Flashcard` (Services/Storage) stores the fields this
/// operates on; keeping the math here makes it independently testable.
enum SpacedRepetition {
    /// How well the learner recalled the card during a review.
    enum Grade: Int, CaseIterable, Codable, Sendable {
        case again = 0
        case hard = 1
        case good = 2
        case easy = 3

        var label: String {
            switch self {
            case .again: return "Again"
            case .hard: return "Hard"
            case .good: return "Good"
            case .easy: return "Easy"
            }
        }
    }

    struct State: Equatable, Sendable {
        var repetitions: Int
        var intervalDays: Double
        var easeFactor: Double
        var dueDate: Date

        static func new(now: Date = Date()) -> State {
            State(repetitions: 0, intervalDays: 0, easeFactor: 2.5, dueDate: now)
        }
    }

    static let minEaseFactor = 1.3
    static let maxIntervalDays = 365.0

    /// On a lapse (`.again`) the card resets to a short same-day relearning
    /// step; otherwise the interval grows using a SM-2-derived ease factor.
    static func schedule(_ state: State, grade: Grade, now: Date = Date()) -> State {
        let easeDelta: Double
        switch grade {
        case .again: easeDelta = -0.8
        case .hard: easeDelta = -0.15
        case .good: easeDelta = 0
        case .easy: easeDelta = 0.15
        }
        let ease = max(minEaseFactor, state.easeFactor + easeDelta)

        var repetitions = state.repetitions
        var interval: Double

        if grade == .again {
            repetitions = 0
            interval = 1.0 / 24.0 // ~1 hour relearning step, due again the same day
        } else {
            repetitions += 1
            switch repetitions {
            case 1:
                interval = grade == .easy ? 4 : 1
            case 2:
                interval = grade == .easy ? 7 : 3
            default:
                interval = max(1, state.intervalDays) * ease
                if grade == .hard { interval *= 0.8 }
            }
        }

        interval = min(max(interval, 1.0 / 24.0), maxIntervalDays)
        let dueDate = now.addingTimeInterval(interval * 86400)
        return State(repetitions: repetitions, intervalDays: interval, easeFactor: ease, dueDate: dueDate)
    }
}
