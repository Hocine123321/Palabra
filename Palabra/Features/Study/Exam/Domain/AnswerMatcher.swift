import Foundation

/// Decides how right a typed answer is, the way a teacher would: a missing accent or one typo is not a wrong answer.
enum AnswerMatcher {
    struct Grade: Equatable {
        enum Kind: Equatable {
            case exact
            /// Right letters, accents missing or different.
            case accentsMissed
            /// One or two letters off.
            case typo
            case wrong
        }

        var kind: Kind
        var score: Double
    }

    static let accentsMissedScore = 0.75
    static let typoScore = 0.5

    /// Lowercase, no punctuation, one space between words. Accents are kept.
    static func normalize(_ text: String) -> String {
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "es"))
        let kept = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(kept).split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// `normalize` with accents (and the tilde of ñ) removed.
    static func fold(_ text: String) -> String {
        normalize(text).folding(options: .diacriticInsensitive, locale: nil)
    }

    /// English answers may leave out "to", "the", "a", "an": "speak" is right for "to speak".
    static func stripEnglishFiller(_ normalized: String) -> String {
        for filler in ["to ", "the ", "an ", "a "] where normalized.hasPrefix(filler) && normalized.count > filler.count {
            return String(normalized.dropFirst(filler.count))
        }
        return normalized
    }

    /// "to speak; to talk (informal)" -> ["to speak", "to talk"]. Brackets are explanations, not part of the answer.
    static func alternatives(of text: String) -> [String] {
        let withoutBrackets = text.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        let parts = withoutBrackets
            .components(separatedBy: CharacterSet(charactersIn: ",;/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts
    }

    /// Edit distance (insert, delete, change one letter).
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[y.count]
    }

    /// How many letters off still counts as a typo: none for short words, one for medium, two for long ones.
    private static func typoAllowance(forLength length: Int) -> Int {
        if length >= 9 { return 2 }
        if length >= 4 { return 1 }
        return 0
    }

    static func grade(typed: String, accepted: [String], english: Bool = false) -> Grade {
        func prepare(_ text: String) -> String {
            let normalized = normalize(text)
            return english ? stripEnglishFiller(normalized) : normalized
        }
        let given = prepare(typed)
        guard !given.isEmpty else { return Grade(kind: .wrong, score: 0) }
        let givenFolded = given.folding(options: .diacriticInsensitive, locale: nil)
        var best = Grade(kind: .wrong, score: 0)
        for answer in accepted {
            let options = english ? alternatives(of: answer) + [answer] : [answer]
            for option in options {
                let expected = prepare(option)
                guard !expected.isEmpty else { continue }
                if expected == given { return Grade(kind: .exact, score: 1) }
                let expectedFolded = expected.folding(options: .diacriticInsensitive, locale: nil)
                if expectedFolded == givenFolded, best.score < accentsMissedScore {
                    best = Grade(kind: .accentsMissed, score: accentsMissedScore)
                } else if best.score < typoScore,
                          distance(givenFolded, expectedFolded) <= typoAllowance(forLength: expectedFolded.count),
                          distance(givenFolded, expectedFolded) > 0 {
                    best = Grade(kind: .typo, score: typoScore)
                }
            }
        }
        return best
    }

    /// Words of a sentence as the person sees them (punctuation stays attached).
    static func tokens(of sentence: String) -> [String] {
        sentence.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 1 when every word is in its place, otherwise the share of places that are right.
    static func orderScore(given: [String], answer: [String]) -> Double {
        guard !answer.isEmpty else { return 0 }
        var right = 0
        for (index, token) in answer.enumerated() where index < given.count && fold(given[index]) == fold(token) { right += 1 }
        return Double(right) / Double(answer.count)
    }
}

/// Finds a word (or one of its forms) inside an example sentence and blanks it out.
enum ClozeFinder {
    struct Cloze: Equatable {
        /// The sentence with the word replaced by `blank`.
        let blanked: String
        /// The word as it was written in the sentence (a conjugated form, say).
        let answer: String
        let full: String
    }

    static let blank = "_____"

    static func make(sentence: String, candidates: [String]) -> Cloze? {
        guard AnswerMatcher.tokens(of: sentence).count >= 3 else { return nil }
        var seen = Set<String>()
        let ordered = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(AnswerMatcher.fold($0)).inserted }
            .sorted { $0.count > $1.count }
        for candidate in ordered {
            var searchRange = sentence.startIndex..<sentence.endIndex
            while let found = sentence.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if isWholeWord(found, in: sentence) {
                    var blanked = sentence
                    blanked.replaceSubrange(found, with: blank)
                    return Cloze(blanked: blanked, answer: String(sentence[found]), full: sentence)
                }
                searchRange = found.upperBound..<sentence.endIndex
            }
        }
        return nil
    }

    private static func isWholeWord(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}
