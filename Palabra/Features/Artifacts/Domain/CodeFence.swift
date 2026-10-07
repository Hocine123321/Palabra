import Foundation

/// Models sometimes wrap JSON in a Markdown code fence even when told not to.
enum CodeFence {
    static func strip(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let newline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: newline)...])
        } else {
            s = String(s.dropFirst(3))
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
