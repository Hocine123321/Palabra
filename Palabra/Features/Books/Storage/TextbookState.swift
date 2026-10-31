import Foundation

/// How big lesson text is, relative to the system text size.
enum ReaderTextSize: Int, Codable, CaseIterable, Identifiable, Sendable {
    case smaller = -1
    case standard = 0
    case larger = 1
    case largest = 2

    var id: Int { rawValue }
}

struct ReaderPreferences: Codable, Equatable {
    var recallLevel: RecallLevel = .essential
    var textSize: ReaderTextSize = .standard

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReaderPreferences()
        recallLevel = (try? c.decodeIfPresent(RecallLevel.self, forKey: .recallLevel)) ?? defaults.recallLevel
        textSize = (try? c.decodeIfPresent(ReaderTextSize.self, forKey: .textSize)) ?? defaults.textSize
    }
}

struct BookProgress: Codable, Equatable {
    var lastPageID: String?
    /// Every page that was opened. Ids of pages that no longer exist are ignored when counting.
    var visitedPageIDs: Set<String> = []
    /// The page the bookmark sits on (`lesson/page`), if the person placed one.
    var bookmarkPageID: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastPageID = try c.decodeIfPresent(String.self, forKey: .lastPageID)
        visitedPageIDs = try c.decodeIfPresent(Set<String>.self, forKey: .visitedPageIDs) ?? []
        bookmarkPageID = try c.decodeIfPresent(String.self, forKey: .bookmarkPageID)
    }
}

/// Everything the textbook feature saves about the person: where they stopped in each book and how they like to read.
/// The lessons themselves are never stored here, so adding or rewriting a lesson cannot touch any of this.
struct TextbookState: Codable, Equatable {
    /// Keyed by book id.
    var progress: [String: BookProgress] = [:]
    var preferences = ReaderPreferences()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        progress = try c.decodeIfPresent([String: BookProgress].self, forKey: .progress) ?? [:]
        preferences = try c.decodeIfPresent(ReaderPreferences.self, forKey: .preferences) ?? ReaderPreferences()
    }
}

/// UserDefaults storage for `TextbookState`, as one JSON blob that tolerates added and missing fields.
final class TextbookStateStore {
    static let defaultsKey = "textbookState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var value: TextbookState {
        get {
            guard let data = defaults.data(forKey: Self.defaultsKey),
                  let saved = try? JSONDecoder().decode(TextbookState.self, from: data) else { return TextbookState() }
            return saved
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.defaultsKey)
        }
    }
}
