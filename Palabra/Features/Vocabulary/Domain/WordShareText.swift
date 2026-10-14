import Foundation

/// The plain text sent by Share on a word: the word, what it means, and one example with its translation.
enum WordShareText {
    static func make(_ content: WordContent) -> String {
        var lines = [content.word]
        let translations = content.meaning.translations.filter { !$0.isEmpty }
        if !translations.isEmpty { lines[0] += " \u{2014} " + translations.joined(separator: ", ") }
        if let example = content.examples.first {
            lines.append("")
            lines.append(example.spanish)
            if !example.english.isEmpty { lines.append(example.english) }
        }
        return lines.joined(separator: "\n")
    }
}
