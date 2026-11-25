import Foundation

/// One space-separated piece of a sentence, with where it sits in the sentence (UTF-16 offsets, the
/// units the speech synthesizer reports) and the word inside it without punctuation.
struct SentenceChunk: Equatable {
    var text: String
    /// `text` without leading or trailing punctuation: "¿Cómo" → "Cómo". Empty for a lone symbol.
    var core: String
    var range: NSRange
}

enum SentenceTokens {
    private static let edge = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)

    static func chunks(of sentence: String) -> [SentenceChunk] {
        let ns = sentence as NSString
        var result: [SentenceChunk] = []
        var start: Int?
        func close(at end: Int) {
            guard let begin = start else { return }
            let range = NSRange(location: begin, length: end - begin)
            let text = ns.substring(with: range)
            result.append(SentenceChunk(text: text, core: text.trimmingCharacters(in: edge), range: range))
            start = nil
        }
        var index = 0
        while index < ns.length {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: index)) ?? "a")
            if isSpace { close(at: index) } else if start == nil { start = index }
            index += 1
        }
        close(at: ns.length)
        return result
    }

    /// Whether the word being spoken (a character range from the synthesizer) falls inside `chunk`.
    static func isSpoken(_ chunk: SentenceChunk, at spoken: NSRange?) -> Bool {
        guard let spoken else { return false }
        return spoken.location >= chunk.range.location && spoken.location < chunk.range.location + chunk.range.length
    }
}
