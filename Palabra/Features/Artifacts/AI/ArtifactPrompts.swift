import Foundation

enum ArtifactPrompts {
    static let payloadMarker = "---PAYLOAD---"
    static let endMarker = "---END---"
    static let currentPayloadHeader = "CURRENT PAYLOAD:"

    /// The user's request goes in the prompt, never here. The capability manual is generated from
    /// the registry, so a new capability is learnable by the AI with no prompt edits.
    /// Plan B2 adds the app-kind rules; until then only `spec` is offered.
    static func systemInstruction(registry: CapabilityRegistry, language: SupportedLanguage, allowedKinds: Set<ArtifactKind>) -> String {
        let kinds = allowedKinds.map(\.rawValue).sorted().joined(separator: ", ")
        let classes: Set<CapabilityClass> = allowedKinds.contains(.app) ? [.read, .write, .ai, .local] : [.read]
        return """
        You build "artifacts" for Palabra, an app that helps one person learn Spanish. An artifact is a table, chart, roadmap, checklist or similar page that the app saves and shows. Answer with the artifact only.

        OUTPUT FORMAT (follow exactly; no text before or after, no code fences):
        {"kind":"spec","title":"<short name, at most \(ArtifactGeneratorLimits.maxTitleLength) characters>","requests":["<capability names the artifact reads>"]}
        \(payloadMarker)
        {"blocks":[ ...blocks... ]}
        \(endMarker)
        Always finish with \(endMarker). The "kind" must be one of: \(kinds).

        BLOCKS you may use (each is a JSON object in "blocks"):
        \(SpecBlock.catalog)

        LIVE DATA: a table or chart can show the user's own app data through "bind". The app keeps bound data up to date by itself, so prefer "bind" over copying numbers into the artifact. Capabilities you may bind to:
        \(registry.manual(including: classes))

        RULES
        - Keep it compact: at most 40 blocks and short text. Never exceed the size the answer can hold.
        - Write all visible text in \(language.instructionName). Spanish words and phrases stay in Spanish.
        - Never invent the user's own data (their words, counts or progress): bind to a capability for that. Teaching content you write yourself (weekday names, a study roadmap) is fine.
        - "requests" lists exactly the capabilities used by a "bind", and nothing else.
        """
    }

    /// The prompt for changing an existing artifact: the whole current payload plus the change.
    static func updatePrompt(change: String, currentTitle: String, currentPayload: String) -> String {
        """
        Change request: \(change)

        Apply the change and return the complete new artifact in the output format. Keep everything the change request does not touch.

        TITLE: \(currentTitle)
        \(currentPayloadHeader)
        \(currentPayload)
        """
    }

    /// Appended to the same prompt for the single automatic retry.
    static func retryAddendum(for error: ArtifactGenError) -> String {
        switch error {
        case .truncated:
            return "YOUR PREVIOUS ANSWER WAS CUT OFF before \(endMarker). Make the artifact smaller: fewer blocks, shorter text. Finish with \(endMarker)."
        case .invalidSpec(let detail):
            return "YOUR PREVIOUS ANSWER COULD NOT BE USED: \(detail). Fix that and follow the output format exactly."
        case .malformedEnvelope(let detail):
            return "YOUR PREVIOUS ANSWER WAS NOT IN THE OUTPUT FORMAT: \(detail). Follow the output format exactly."
        case .ai, .kindNotAvailable, .tooLargeToExtend:
            return ""
        }
    }
}
