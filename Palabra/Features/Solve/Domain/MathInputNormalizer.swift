import Foundation

/// Cleans text typed or read from a photo into something Wolfram|Alpha understands.
/// Pure and conservative: it only rewrites symbols that mean one thing.
enum MathInputNormalizer {
    static let maxLength = 400

    static func normalize(_ raw: String) -> String {
        var text = raw
        // Question numbering at the very start: "1.", "2)", "a)", "Q3:" (never "(1)", which can be maths).
        text = text.replacingOccurrences(of: "^\\s*(?:Q\\s*[0-9]{1,2}\\s*[:.)]|[0-9]{1,2}[.)]|[a-d][.)])\\s+", with: "", options: .regularExpression)

        let simple: [(String, String)] = [
            ("\u{2212}", "-"), ("\u{2013}", "-"), ("\u{2014}", "-"),
            ("\u{00D7}", "*"), ("\u{22C5}", "*"), ("\u{00B7}", "*"),
            ("\u{00F7}", "/"), ("\u{2215}", "/"),
            ("\u{03C0}", "pi"), ("\u{221E}", "infinity"),
            ("\u{2264}", "<="), ("\u{2265}", ">="), ("\u{2260}", "!="),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
        ]
        for (from, to) in simple { text = text.replacingOccurrences(of: from, with: to) }

        text = convertSuperscripts(text)
        text = text.replacingOccurrences(of: "\u{221A}\\s*\\(", with: "sqrt(", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{221A}\\s*([0-9A-Za-z.]+)", with: "sqrt($1)", options: .regularExpression)

        // Lines and runs of spaces become single spaces.
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(maxLength))
    }

    /// Two inputs that mean the same ask the same question: lowercase, no spaces.
    static func key(for normalized: String) -> String {
        normalized.lowercased().filter { !$0.isWhitespace }
    }

    private static let superscripts: [Character: Character] = [
        "\u{2070}": "0", "\u{00B9}": "1", "\u{00B2}": "2", "\u{00B3}": "3", "\u{2074}": "4",
        "\u{2075}": "5", "\u{2076}": "6", "\u{2077}": "7", "\u{2078}": "8", "\u{2079}": "9",
    ]

    /// "x²" -> "x^2", "x¹⁰" -> "x^10".
    private static func convertSuperscripts(_ text: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            if !run.isEmpty { result += "^" + run; run = "" }
        }
        for character in text {
            if let digit = superscripts[character] {
                run.append(digit)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}
