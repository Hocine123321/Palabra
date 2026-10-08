import Foundation

enum ArtifactGenError: Error, Equatable {
    case ai(AIError)
    /// The output hit the token cap (no `---END---`, or the client reported `.truncated`).
    case truncated
    case malformedEnvelope(String)
    case invalidSpec(String)
    case invalidApp(String)
    case kindNotAvailable
    case tooLargeToExtend

    /// Shown to the person; localized by `LocalizedStringKey` lookup at the call site.
    var userMessage: String {
        switch self {
        case .ai(let error): return error.userMessage
        case .truncated: return "The AI's answer was cut off. Try asking for something smaller."
        case .malformedEnvelope: return "The AI's answer wasn't in the expected format. Try again."
        case .invalidSpec: return "The AI returned something that couldn't be shown. Try again or rephrase."
        case .invalidApp: return "The AI returned an app that couldn't be run. Try again or rephrase."
        case .kindNotAvailable: return "That kind of artifact isn't supported yet. Ask for a table, chart, roadmap or checklist."
        case .tooLargeToExtend: return "This artifact is too large to extend. Ask for a simpler version."
        }
    }
}

struct ArtifactEnvelope: Equatable {
    var kind: ArtifactKind
    var title: String
    var requests: [String]
    var payload: String
}

enum ArtifactEnvelopeParser {
    /// Parses `{header JSON}` `---PAYLOAD---` `payload` `---END---`.
    static func parse(_ text: String) -> Result<ArtifactEnvelope, ArtifactGenError> {
        guard let marker = text.range(of: ArtifactPrompts.payloadMarker) else {
            return .failure(.malformedEnvelope("the \(ArtifactPrompts.payloadMarker) line is missing"))
        }
        guard let end = text.range(of: ArtifactPrompts.endMarker, options: .backwards, range: marker.upperBound..<text.endIndex) else {
            return .failure(.truncated)
        }
        let header = String(text[..<marker.lowerBound])
        let payload = CodeFence.strip(String(text[marker.upperBound..<end.lowerBound]))
        guard !payload.isEmpty else { return .failure(.malformedEnvelope("the payload is empty")) }

        guard let object = JSONValue.parse(jsonObjectText(in: header))?.objectValue else {
            return .failure(.malformedEnvelope("the header line is not a JSON object"))
        }
        guard let kind = object["kind"]?.stringValue.flatMap(ArtifactKind.init(rawValue:)) else {
            return .failure(.malformedEnvelope("kind must be \"spec\" or \"app\""))
        }
        let title = String((object["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(ArtifactGeneratorLimits.maxTitleLength))
        let requests = object["requests"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return .success(ArtifactEnvelope(kind: kind, title: title.isEmpty ? "Untitled" : title, requests: requests, payload: payload))
    }

    /// The header may carry a code fence or a stray sentence; take the outermost `{ … }`.
    private static func jsonObjectText(in header: String) -> String {
        let stripped = CodeFence.strip(header)
        guard let open = stripped.firstIndex(of: "{"), let close = stripped.lastIndex(of: "}"), open < close else { return stripped }
        return String(stripped[open...close])
    }
}
