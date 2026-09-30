import Foundation

/// Pure grouping, search and ordering for the sectioned library, kept free of
/// SwiftUI/SwiftData so it can be unit tested with plain values.
enum LibrarySections {
    struct Section: Equatable {
        var title: String
        var words: [Word]
        /// `true` for the bucket holding words that have no section yet.
        var isUnorganized: Bool = false

        static func == (l: Section, r: Section) -> Bool {
            l.title == r.title && l.isUnorganized == r.isUnorganized && l.words.map(\.id) == r.words.map(\.id)
        }
    }

    /// Case- and accent-insensitive match on the word, its translation and any tag.
    /// A leading "#" restricts the match to tags ("#verb").
    static func matches(_ word: Word, query rawQuery: String) -> Bool {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let tagOnly = trimmed.hasPrefix("#")
        let q = WordKey.search(tagOnly ? String(trimmed.dropFirst()) : trimmed)
        guard !q.isEmpty else { return true }
        let tagHit = word.tags.contains { WordKey.search($0).contains(q) }
        if tagOnly { return tagHit }
        let categoryHit = word.category.map { WordKey.search($0).contains(q) } ?? false
        return word.searchKey.contains(q)
            || WordKey.search(word.translation).contains(q)
            || tagHit || categoryHit
    }

    static func group(_ words: [Word], order: OrganizerSettings.SectionOrder, unorganizedTitle: String) -> [Section] {
        var buckets: [String: [Word]] = [:]
        var unorganized: [Word] = []
        for word in words {
            if let category = word.category, !category.isEmpty {
                buckets[category, default: []].append(word)
            } else {
                unorganized.append(word)
            }
        }
        var sections = buckets.map { Section(title: $0.key, words: $0.value) }
        func newest(_ s: Section) -> Date { s.words.map(\.createdAt).max() ?? .distantPast }
        switch order {
        case .alphabetical:
            sections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .largestFirst:
            sections.sort {
                $0.words.count != $1.words.count
                    ? $0.words.count > $1.words.count
                    : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .recentlyAdded:
            sections.sort { newest($0) > newest($1) }
        }
        if !unorganized.isEmpty {
            sections.append(Section(title: unorganizedTitle, words: unorganized, isUnorganized: true))
        }
        return sections
    }

    /// All tags with their word counts, most used first.
    static func tagCounts(_ words: [Word]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for word in words { for tag in word.tags { counts[tag, default: 0] += 1 } }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }
}
