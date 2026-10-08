import Foundation

enum ArtifactPrompts {
    static let payloadMarker = "---PAYLOAD---"
    static let endMarker = "---END---"
    static let currentPayloadHeader = "CURRENT PAYLOAD:"

    /// The user's request goes in the prompt, never here. The capability manual is generated from
    /// the registry, so a new capability is learnable by the AI with no prompt edits.
    /// The app-kind rules are included only when `.app` is allowed.
    static func systemInstruction(registry: CapabilityRegistry, language: SupportedLanguage, allowedKinds: Set<ArtifactKind>) -> String {
        let kinds = allowedKinds.map(\.rawValue).sorted().joined(separator: ", ")
        let appAllowed = allowedKinds.contains(.app)
        let classes: Set<CapabilityClass> = appAllowed ? [.read, .write, .ai, .local] : [.read]
        let requestsRule = appAllowed
            ? "- \"requests\" lists exactly the capabilities a spec binds to, or an app calls with palabra.call (storage.* needs no request)."
            : "- \"requests\" lists exactly the capabilities used by a \"bind\", and nothing else."
        let appSection = appAllowed ? appRules : ""
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

        LIVE DATA: a table or chart can show the user's own app data through "bind". The app keeps bound data up to date by itself, so prefer "bind" over copying numbers into the artifact. Capabilities you may bind to or call:
        \(registry.manual(including: classes))
        \(appSection)
        RULES
        - Keep it compact: at most 40 blocks and short text. Never exceed the size the answer can hold.
        - Write all visible text in \(language.instructionName). Spanish words and phrases stay in Spanish.
        - Never invent the user's own data (their words, counts or progress): bind to a capability for that. Teaching content you write yourself (weekday names, a study roadmap) is fine.
        \(requestsRule)
        """
    }

    /// Only shown when the app kind is allowed. Keep in sync with `ArtifactSandbox` and `ArtifactHTMLLint`.
    private static let appRules = """

        APP ARTIFACTS (kind "app"): choose "app" only when the person asked for something interactive (a practice game, a simulator, a tracker with buttons). For tables, charts, roadmaps and checklists use kind "spec".
        An app's output is the same format with "kind":"app" and ONE self-contained HTML document as the payload:
        {"kind":"app","title":"<short name>","requests":["library.words","ai.generate"]}
        \(payloadMarker)
        <html>…</html>
        \(endMarker)
        - At most 20 KB. No external URLs of any kind (no CDN, web fonts, web images, requests to the web): inline all CSS and JavaScript; images only as data: URIs.
        - Never use localStorage, sessionStorage or cookies. Save with palabra.call("storage.set",{key,value}) and read with palabra.call("storage.get",{key}).
        - Talk to the app only through palabra.call(name, args). It returns a Promise that resolves to the value and rejects with {code, message}. Always handle the rejection and show a friendly message.
        - palabra.granted lists the capabilities the person allowed; if one you need is missing, say so in the page.
        - Style with the CSS variables --ink, --ink-secondary, --surface, --accent, --error, --background (they follow light and dark mode). Use palabra.locale ("en" or "ar") for the page's own text and palabra.dir ("ltr" or "rtl") for layout: set it on <html dir>.

        """

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
        case .invalidApp(let detail):
            return "YOUR PREVIOUS ANSWER COULD NOT BE USED: \(detail). Fix that and follow the output format exactly."
        case .malformedEnvelope(let detail):
            return "YOUR PREVIOUS ANSWER WAS NOT IN THE OUTPUT FORMAT: \(detail). Follow the output format exactly."
        case .ai, .kindNotAvailable, .tooLargeToExtend:
            return ""
        }
    }
}
