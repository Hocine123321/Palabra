import Foundation

/// Prepares an answer pasted from an external AI so the normal envelope parser can read it.
/// The answer is normally a page of HTML (copied from an artifact, a file or a chat reply), possibly with chat text and a code
/// fence around it. An old-style envelope is still accepted.
enum ArtifactImport {
    /// Room for the chat text a pasted answer may carry around the page.
    static let chatSlackBytes = 64 * 1024
    /// The most text ever read: the biggest page storage accepts, plus the chat around it.
    static let maxInputBytes = ArtifactOutputBudget.storageMaxBytes + chatSlackBytes

    private static let titlePattern = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let callPattern = try? NSRegularExpression(pattern: #"palabra\.call\(\s*["']([A-Za-z0-9_.]+)["']"#)

    /// An answer with the `---PAYLOAD---` line is returned as it is. Otherwise the HTML document inside it (from `<!doctype`
    /// or `<html` to the last `</html>`) is wrapped into an app envelope: title from `<title>`, requests from the
    /// `palabra.call("…")` names it uses. Text with no HTML document is returned unchanged, so the parser reports it as malformed.
    static func normalize(_ text: String, registry: CapabilityRegistry) -> String {
        if text.contains(ArtifactPrompts.payloadMarker) { return text }
        let opens = [text.range(of: "<!doctype", options: .caseInsensitive), text.range(of: "<html", options: .caseInsensitive)].compactMap { $0 }
        guard let start = opens.map(\.lowerBound).min(),
              let end = text.range(of: "</html>", options: [.caseInsensitive, .backwards]),
              start < end.upperBound
        else { return text }
        let html = String(text[start..<end.upperBound])
        let header: [String: Any] = ["kind": "app", "title": firstMatch(titlePattern, in: html) ?? "", "requests": calls(in: html)]
        guard let data = try? JSONSerialization.data(withJSONObject: header, options: [.withoutEscapingSlashes, .sortedKeys]) else { return text }
        return String(decoding: data, as: UTF8.self) + "\n\(ArtifactPrompts.payloadMarker)\n" + html + "\n\(ArtifactPrompts.endMarker)"
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex?.firstMatch(in: text, range: range), let found = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[found]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func calls(in html: String) -> [String] {
        let range = NSRange(html.startIndex..., in: html)
        let names = (callPattern?.matches(in: html, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
        return Array(Set(names)).sorted()
    }
}
