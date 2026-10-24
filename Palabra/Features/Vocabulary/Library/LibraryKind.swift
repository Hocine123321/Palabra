import Foundation

/// Which entries the Library shows: single words ("hola") or phrases and sentences ("cómo estás"), or both.
/// An entry is a phrase when its headword has more than one word; nothing is stored for this, so every existing
/// library is split correctly the first time the tab is used.
enum LibraryKind: String, CaseIterable, Identifiable {
    case all, words, phrases

    var id: String { rawValue }

    /// A localization key.
    var title: String {
        switch self {
        case .all: return "All"
        case .words: return "Words"
        case .phrases: return "Phrases"
        }
    }

    static func isPhrase(_ headword: String) -> Bool {
        headword.trimmingCharacters(in: .whitespacesAndNewlines).contains { $0.isWhitespace }
    }

    func includes(_ headword: String) -> Bool {
        switch self {
        case .all: return true
        case .words: return !Self.isPhrase(headword)
        case .phrases: return Self.isPhrase(headword)
        }
    }

    func includes(_ word: Word) -> Bool { includes(word.spanish) }
}
