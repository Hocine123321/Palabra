import Foundation

/// Keeps maths readable next to Arabic. In a right-to-left line the neutral characters of a formula
/// ("x = -2", "x^2 - 4 = 0", "(a) 3") are reordered by the bidirectional algorithm and come out mirrored.
/// Wrapping each formula in a left-to-right isolate (U+2066 ... U+2069) keeps it intact while the Arabic around it
/// still reads right to left.
enum BidiText {
    static let leftToRightIsolate = "\u{2066}"
    static let popIsolate = "\u{2069}"

    /// True when the text has any Arabic-script letter.
    static func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isArabic)
    }

    private static func isArabic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }

    /// A whole line that is a formula (or any left-to-right text): kept in one piece.
    static func isolated(_ text: String) -> String {
        text.isEmpty ? text : leftToRightIsolate + text + popIsolate
    }

    /// Characters a formula run is made of. Spaces between two of these stay inside the run.
    private static let formulaToken = "[A-Za-z0-9\u{00B0}\u{00B1}\u{00B2}\u{00B3}\u{00D7}\u{00F7}\u{03C0}\u{221A}\u{221E}\u{2248}\u{2260}\u{2264}\u{2265}\u{2212}^=+*/<>()\\[\\]{}|%_.,:;\\-]+"
    private static let formulaRun = try! NSRegularExpression(pattern: "\(formulaToken)(?: +\(formulaToken))*")

    /// Wraps every formula inside a line of Arabic text in an isolate. A run with no letter or digit (a lone "." or
    /// "-") is left alone, and sentence punctuation after a formula stays outside it.
    static func isolateFormulas(in line: String) -> String {
        let ns = line as NSString
        let matches = formulaRun.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return line }
        var result = ""
        var cursor = 0
        for match in matches {
            var range = match.range
            var run = ns.substring(with: range)
            // Sentence punctuation that ends the run belongs to the Arabic sentence.
            while let last = run.last, ".,:;".contains(last) { run.removeLast() }
            range.length = (run as NSString).length
            guard run.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            result += isolated(run)
            cursor = range.location + range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// What to put on screen for one line of an answer or problem. Plain English text in a left-to-right screen is
    /// returned unchanged (so copying it gives exactly what was written).
    /// - Arabic text: its formulas are isolated.
    /// - A formula line on a right-to-left screen: isolated whole.
    static func display(_ line: String, rightToLeftLayout: Bool) -> String {
        if containsArabic(line) { return isolateFormulas(in: line) }
        return rightToLeftLayout ? isolated(line) : line
    }

    private static let numberedPattern = try! NSRegularExpression(pattern: "^\\s*([0-9]{1,2})[.)]\\s+(.+)$")

    /// One numbered line ("3. text") split into its number and text, so the number can sit in its own column.
    static func numberedLine(_ line: String) -> (number: Int, text: String)? {
        let ns = line as NSString
        guard let match = numberedPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let number = Int(ns.substring(with: match.range(at: 1))) else { return nil }
        let text = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }
}
