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

    /// For a reply that should be one JSON value: unwraps a fence at the start, and also a fence that follows a line of
    /// chatter ("Here is the JSON:" then a fenced block). A reply that already starts with `{` or `[` is left alone, so a
    /// ``` inside a string value is never mistaken for a fence.
    static func extractJSON(_ text: String) -> String {
        let stripped = strip(text)
        guard let first = stripped.first, first != "{", first != "[" else { return stripped }
        guard let open = stripped.range(of: "```") else { return stripped }
        let afterOpen = stripped[open.upperBound...]
        guard let lineEnd = afterOpen.firstIndex(of: "\n"),
              let close = afterOpen[lineEnd...].range(of: "```", options: .backwards) else { return stripped }
        let inner = afterOpen[afterOpen.index(after: lineEnd)..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? stripped : inner
    }
}
