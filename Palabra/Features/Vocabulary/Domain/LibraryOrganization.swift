import Foundation

/// AI-assigned placement for one word: one section ("category") and several tags.
struct WordPlacement: Codable, Equatable, Sendable {
    var category: String
    var tags: [String]
}

/// One word sent to the organizer: enough to classify it without the full content.
struct OrganizerWordInput: Codable, Equatable, Sendable {
    var word: String
    var translation: String
    var partOfSpeech: String
}

/// The organizer's answer for one batch, keyed by the word exactly as sent.
struct OrganizerBatchResult: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var word: String
        var category: String
        var tags: [String]
    }
    var entries: [Entry]
}

/// Cleans up whatever the AI returns so the library never shows blank,
/// duplicate or runaway section/tag names.
enum LibraryTaxonomy {
    static let fallbackCategory = "Other"
    static let maxTagsPerWord = 6
    static let maxNameLength = 32

    static func cleanName(_ raw: String) -> String {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let clipped = collapsed.count > maxNameLength ? String(collapsed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces) : collapsed
        guard let first = clipped.first else { return "" }
        return first.uppercased() + clipped.dropFirst()
    }

    static func cleanTag(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        return t.count > maxNameLength ? String(t.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces) : t
    }

    static func cleanTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in raw.map(cleanTag) where !tag.isEmpty && seen.insert(tag).inserted {
            out.append(tag)
            if out.count == maxTagsPerWord { break }
        }
        return out
    }

    static func clean(_ placement: WordPlacement) -> WordPlacement {
        let category = cleanName(placement.category)
        return WordPlacement(category: category.isEmpty ? fallbackCategory : category, tags: cleanTags(placement.tags))
    }

    /// Merges near-duplicate section names (case/diacritic/plural-insensitive) onto
    /// an already-known spelling, so "Food" and "food" never become two sections.
    static func canonicalCategory(_ name: String, known: [String]) -> String {
        func norm(_ s: String) -> String {
            var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if t.count > 3, t.hasSuffix("s") { t.removeLast() }
            return t
        }
        let target = norm(name)
        return known.first { norm($0) == target } ?? name
    }
}
