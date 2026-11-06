import Foundation

enum ArtifactPrompts {
    static let payloadMarker = "---PAYLOAD---"
    static let endMarker = "---END---"
    static let currentPayloadHeader = "CURRENT PAYLOAD:"

    /// The user's request goes in the prompt, never here. The capability manual is generated from
    /// the registry, so a new capability is learnable by the AI with no prompt edits.
    /// The app-kind rules are included only when `.app` is allowed.
    static func systemInstruction(registry: CapabilityRegistry, language: SupportedLanguage, allowedKinds: Set<ArtifactKind>, maxKB: Int = ArtifactOutputBudget.defaultKB) -> String {
        let kinds = allowedKinds.map(\.rawValue).sorted().joined(separator: ", ")
        let appAllowed = allowedKinds.contains(.app)
        let classes: Set<CapabilityClass> = appAllowed ? [.read, .write, .ai, .local] : [.read]
        let requestsRule = appAllowed
            ? "- \"requests\" lists exactly the capabilities a spec binds to, or an app calls with palabra.call (storage.* needs no request)."
            : "- \"requests\" lists exactly the capabilities used by a \"bind\", and nothing else."
        let appSection = appAllowed ? appRules(maxKB: maxKB) : ""
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
    private static func appRules(maxKB: Int) -> String {
        """

        APP ARTIFACTS (kind "app"): choose "app" only when the person asked for something interactive (a practice game, a simulator, a tracker with buttons). For tables, charts, roadmaps and checklists use kind "spec".
        An app's output is the same format with "kind":"app" and ONE self-contained HTML document as the payload:
        {"kind":"app","title":"<short name>","requests":["library.words","ai.generate"]}
        \(payloadMarker)
        <html>…</html>
        \(endMarker)
        - At most \(ArtifactOutputBudget.clampedKB(maxKB)) KB, and only as large as the request needs: a small app is better than a padded one.
        \(sandboxRules)

        """
    }

    /// What an HTML page must obey to run in the sandbox, whoever wrote it. Shared by the in-app prompt (Gemini) and the one the
    /// person copies into another AI, so the two cannot drift.
    static let sandboxRules = """
    - No external URLs of any kind (no CDN, web fonts, web images, requests to the web): inline all CSS and JavaScript; images only as data: URIs.
    - Never use localStorage, sessionStorage or cookies. Save with palabra.call("storage.set",{key,value}) and read with palabra.call("storage.get",{key}).
    - Talk to the app only through palabra.call(name, args). It returns a Promise that resolves to the value and rejects with {code, message}. Always handle the rejection and show a friendly message.
    - palabra.granted lists the capabilities the person allowed; if one you need is missing, say so in the page.
    - Style with the CSS variables --ink, --ink-secondary, --surface, --accent, --error, --background (they follow light and dark mode). Use palabra.locale ("en" or "ar") for the page's own text and palabra.dir ("ltr" or "rtl") for layout: set it on <html dir>.
    """

    /// What the person copies into Claude, ChatGPT or another full AI app. It describes what the page must be and what it can
    /// call, and nothing about how to deliver it: those apps make an interactive page as an artifact or a file, their own way, and
    /// the person brings it back with Upload/paste (`ArtifactImport` copes with a file, a pasted page or a page inside chat text).
    /// `userPrompt` is what the person wants (or, on update, the change plus the current page). The size is the person's external
    /// cap (Settings → Artifacts), not the cap for the in-app AI.
    static func exportPrompt(userPrompt: String, registry: CapabilityRegistry, language: SupportedLanguage, maxKB: Int = externalMaxKB) -> String {
        """
        Build an interactive page for Palabra, an app that helps one person learn Spanish. It is ONE self-contained HTML page (a table, chart, roadmap, checklist, practice game, simulator or tracker). Palabra saves it and runs it in a sandbox, so it must follow the rules below.

        Make it the way you normally make an interactive page or app (an artifact, a file, whatever your app does). The person will take the finished HTML to Palabra themselves. Give the page a good <title>: it becomes its name.

        RULES
        - At most \(describeLimit(kb: maxKB)), and only as large as the request needs: a focused page is better than a padded one.
        \(sandboxRules)
        - Write all visible text in \(language.instructionName). Spanish words and phrases stay in Spanish.
        - Never invent the user's own data (their words, counts or progress): read it with palabra.call from the capabilities below. Teaching content you write yourself (weekday names, a study roadmap) is fine.

        CAPABILITIES the page may call with palabra.call (a capability that changes data or uses the AI asks the person for approval first):
        \(registry.manual(including: [.read, .write, .ai, .local]))

        REQUEST:
        \(userPrompt)
        """
    }

    /// "512 KB" or "2 MB".
    static func describeLimit(kb: Int) -> String {
        let clamped = ArtifactOutputBudget.clampedExternalKB(kb)
        return clamped % 1024 == 0 ? "\(clamped / 1024) MB" : "\(clamped) KB"
    }

    /// The most an external AI is told it may write (the storage maximum, 2 MB).
    static let externalMaxKB = ArtifactOutputBudget.externalMaxKB

    /// The request for changing a saved page in another AI: the whole current HTML plus the change; the answer is the complete new page.
    static func externalUpdateRequest(change: String, currentTitle: String, currentHTML: String) -> String {
        """
        Change request: \(change)

        Apply the change and give me the complete new page, not just the changed parts. Keep everything the change request does not touch, and keep the same <title>.

        TITLE: \(currentTitle)
        CURRENT PAGE:
        \(currentHTML)
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
        case .invalidApp(let detail):
            return "YOUR PREVIOUS ANSWER COULD NOT BE USED: \(detail). Fix that and follow the output format exactly."
        case .malformedEnvelope(let detail):
            return "YOUR PREVIOUS ANSWER WAS NOT IN THE OUTPUT FORMAT: \(detail). Follow the output format exactly."
        case .ai, .kindNotAvailable, .tooLargeToExtend:
            return ""
        }
    }
}
