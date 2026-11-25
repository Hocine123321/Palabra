import Foundation
import UIKit

/// Offers corrections for a misspelled word. The system's own checker; no AI call.
protocol SpellGuessing {
    /// Possible corrections for `word`; empty when the word is spelled right or no Spanish dictionary exists.
    func guesses(for word: String) -> [String]
}

struct SystemSpellGuesser: SpellGuessing {
    func guesses(for word: String) -> [String] {
        guard let language = UITextChecker.availableLanguages.first(where: { $0.lowercased().hasPrefix("es") }) else { return [] }
        let checker = UITextChecker()
        let whole = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: whole, startingAt: 0, wrap: false, language: language)
        guard miss.location != NSNotFound else { return [] }
        return checker.guesses(forWordRange: miss, in: word, language: language) ?? []
    }
}

/// "Did you mean …?" before the add-word flow spends a request on a typo.
enum SpellSuggestion {
    /// The nearest correction, or nil: phrases, very short or very long input, and words the checker accepts get none.
    /// A guess must be a single word within two edits of what was typed (accents don't count as edits), so a wild
    /// guess never replaces a rare but real word.
    static func suggestion(for input: String, guesser: SpellGuessing = SystemSpellGuesser()) -> String? {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...30).contains(word.count), word.allSatisfy(\.isLetter) else { return nil }
        let typed = WordKey.search(word)
        for guess in guesser.guesses(for: word).prefix(5) {
            let candidate = guess.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty, candidate.allSatisfy(\.isLetter) else { continue }
            let key = WordKey.identity(candidate)
            guard key != WordKey.identity(word), editDistance(typed, WordKey.search(candidate)) <= 2 else { continue }
            return key
        }
        return nil
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
