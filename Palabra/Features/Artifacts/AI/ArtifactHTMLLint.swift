import Foundation

enum ArtifactHTMLLintError: Error, Equatable {
    case missingHTMLTag
    case externalResource(String)
    case localStorage
    case tooLarge

    /// One line for the retry addendum.
    var detail: String {
        switch self {
        case .missingHTMLTag: return "the payload is not an HTML document (no <html> tag)"
        case .externalResource(let found): return "it loads an external resource (\(found)); everything must be inline"
        case .localStorage: return "it uses localStorage; use palabra.call(\"storage.set\" / \"storage.get\") instead"
        case .tooLarge: return "the HTML is larger than \(ArtifactLimits.maxPayloadBytes) bytes; make it much smaller"
        }
    }
}

/// Rejects app HTML that cannot run in the sandbox. Returns the trimmed HTML.
enum ArtifactHTMLLint {
    // A src/href attribute whose value starts with http:, https: or // (protocol-relative).
    private static let externalAttribute = try? NSRegularExpression(pattern: #"(?:src|href)\s*=\s*["']?\s*((?:https?:|//)[^\s"'>]*)"#)

    static func check(_ html: String) -> Result<String, ArtifactHTMLLintError> {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= ArtifactLimits.maxPayloadBytes else { return .failure(.tooLarge) }
        let lower = trimmed.lowercased()
        guard lower.contains("<html") else { return .failure(.missingHTMLTag) }
        if lower.contains("localstorage") { return .failure(.localStorage) }
        let range = NSRange(lower.startIndex..., in: lower)
        if let match = externalAttribute?.firstMatch(in: lower, range: range),
           let found = Range(match.range(at: 1), in: lower) {
            return .failure(.externalResource(String(lower[found].prefix(60))))
        }
        return .success(trimmed)
    }
}
