import Foundation

/// How the Library orders its words (inside sections too). Newest first is the long-standing default.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest, oldest, alphabetical

    var id: String { rawValue }

    /// A localization key.
    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .alphabetical: return "A to Z"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "clock"
        case .oldest: return "clock.arrow.circlepath"
        case .alphabetical: return "textformat.abc"
        }
    }

    func apply(_ words: [Word]) -> [Word] {
        switch self {
        case .newest: return words.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return words.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical: return words.sorted { $0.spanish.localizedStandardCompare($1.spanish) == .orderedAscending }
        }
    }
}
