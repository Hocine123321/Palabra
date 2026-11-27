import Foundation

/// What the Spanish hub's cards show: the word count, the newest few words and the word of the day.
/// A plain value, so the hub never holds a SwiftData model and the logic is testable.
struct HubSummary: Equatable {
    struct RecentWord: Identifiable, Equatable {
        let id: UUID
        let spanish: String
        let key: String
        var translation: String = ""
    }

    /// The word the hub features today.
    struct Highlight: Equatable {
        let id: UUID
        let spanish: String
        let translation: String
        let key: String
    }

    /// How many recent words the card shows.
    static let recentLimit = 3

    let wordCount: Int
    let recent: [RecentWord]
    let highlight: Highlight?

    static let empty = HubSummary(wordCount: 0, recent: [])

    init(wordCount: Int, recent: [RecentWord], highlight: Highlight? = nil) {
        self.wordCount = wordCount
        self.recent = Array(recent.prefix(Self.recentLimit))
        self.highlight = highlight
    }

    /// `words` must be newest first, which is how `WordRepository.allWords()` returns them.
    init(newestFirst words: [Word], on date: Date = Date(), calendar: Calendar = .current) {
        self.init(
            wordCount: words.count,
            recent: words.prefix(Self.recentLimit).map {
                RecentWord(id: $0.id, spanish: $0.spanish, key: $0.key, translation: $0.translation)
            },
            highlight: Self.wordOfTheDay(in: words, on: date, calendar: calendar)
        )
    }

    /// The same word all day and another one tomorrow. The pool is ordered by key, not by when words were added, so adding
    /// a word does not change today's pick unless it lands in the pick's place.
    static func wordOfTheDay(in words: [Word], on date: Date, calendar: Calendar = .current) -> Highlight? {
        guard !words.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let pool = words.sorted { $0.key < $1.key }
        let word = pool[day % pool.count]
        return Highlight(id: word.id, spanish: word.spanish, translation: word.translation, key: word.key)
    }
}
