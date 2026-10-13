import Foundation

/// What the Spanish hub's Library card shows: the word count and the newest few words.
/// A plain value, so the hub never holds a SwiftData model and the logic is testable.
struct HubSummary: Equatable {
    struct RecentWord: Identifiable, Equatable {
        let id: UUID
        let spanish: String
        let key: String
    }

    /// How many recent words the card shows.
    static let recentLimit = 3

    let wordCount: Int
    let recent: [RecentWord]

    static let empty = HubSummary(wordCount: 0, recent: [])

    init(wordCount: Int, recent: [RecentWord]) {
        self.wordCount = wordCount
        self.recent = Array(recent.prefix(Self.recentLimit))
    }

    /// `words` must be newest first, which is how `WordRepository.allWords()` returns them.
    init(newestFirst words: [Word]) {
        self.init(
            wordCount: words.count,
            recent: words.prefix(Self.recentLimit).map { RecentWord(id: $0.id, spanish: $0.spanish, key: $0.key) }
        )
    }
}
