import Foundation
import SwiftUI

/// An unsaved card, as produced by the AI or typed by the person.
/// `id` exists only so SwiftUI can track rows (never use AI text as identity).
struct CardDraft: Identifiable, Equatable {
    var id = UUID()
    var front: String
    var back: String
}

/// What the Vocabulary library tells the Study tool about one word. Plain values,
/// so Study never needs to know about `Word`.
struct VocabularyCardEntry: Equatable {
    let wordID: UUID
    let front: String
    let back: String
}

struct DeckCounts: Equatable {
    var total = 0
    var due = 0
    var new = 0
}

enum StudyRoute: Hashable {
    /// `nil` = every deck.
    case review(UUID?)
    case deck(UUID)
}

extension SRSGrade {
    var title: LocalizedStringKey {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var identifier: String {
        switch self {
        case .again: return "grade-again"
        case .hard: return "grade-hard"
        case .good: return "grade-good"
        case .easy: return "grade-easy"
        }
    }
}

/// Short human label for a delay ("10m", "1d"); the formatter follows the current locale.
enum IntervalLabel {
    static func text(seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        if seconds < 3600 {
            formatter.allowedUnits = [.minute]
        } else if seconds < 86_400 {
            formatter.allowedUnits = [.hour]
        } else if seconds < 86_400 * 30 {
            formatter.allowedUnits = [.day]
        } else if seconds < 86_400 * 365 {
            formatter.allowedUnits = [.month]
        } else {
            formatter.allowedUnits = [.year]
        }
        return formatter.string(from: max(60, seconds)) ?? ""
    }
}
