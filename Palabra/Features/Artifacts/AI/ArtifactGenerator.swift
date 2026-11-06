import Foundation

struct ArtifactDraft: Equatable {
    var kind: ArtifactKind
    var title: String
    /// Sanitized spec JSON (sorted keys), ready to store.
    var payload: Data
    /// Capability names the artifact needs (already filtered and sorted).
    var requests: [String]
    /// What the person asked for (the request, or the change), kept with the saved version.
    var prompt: String
}

enum ArtifactGeneratorLimits {
    static let minRequestLength = 3
    static let maxRequestLength = 4_000
    static let maxTitleLength = 60
}

/// Turns a request into an artifact draft via the generic `generateJSON` call.
/// Nothing is saved here; the caller previews and confirms.
struct ArtifactGenerator {
    let ai: AIClient
    let registry: CapabilityRegistry
    var language: SupportedLanguage = .english
    var allowedKinds: Set<ArtifactKind> = [.spec]
    /// Settings → Artifacts: the most the in-app AI may write for one artifact.
    var maxOutputKB: Int = ArtifactOutputBudget.defaultKB
    /// Set for a pasted external answer: its own byte limit (up to 2 MB), instead of the in-app AI's setting.
    var appByteLimit: Int?
    /// The person's cap for a page from another AI (Settings → Artifacts), in KB.
    var externalMaxKB = ArtifactOutputBudget.externalDefaultKB

    /// The size an app's HTML may reach: the external limit when there is one, else the in-app setting.
    private var allowedAppBytes: Int { appByteLimit ?? ArtifactOutputBudget.bytes(forKB: maxOutputKB) }

    func create(request: String, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError> {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= ArtifactGeneratorLimits.minRequestLength else {
            return .failure(.ai(.validationFailed(["The request is too short."])))
        }
        let text = String(trimmed.prefix(ArtifactGeneratorLimits.maxRequestLength))
        return await run(prompt: text, userPrompt: text, fixedTitle: nil, expectedKind: nil, apiKey: apiKey, model: model)
    }

    /// Sends the current payload plus the change and expects the complete new payload back.
    func update(kind: ArtifactKind, currentTitle: String, currentPayload: Data, change: String, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError> {
        guard allowedKinds.contains(kind) else { return .failure(.kindNotAvailable) }
        let trimmed = change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= ArtifactGeneratorLimits.minRequestLength else {
            return .failure(.ai(.validationFailed(["The change request is too short."])))
        }
        let text = String(trimmed.prefix(ArtifactGeneratorLimits.maxRequestLength))
        let prompt = ArtifactPrompts.updatePrompt(change: text, currentTitle: currentTitle, currentPayload: String(decoding: currentPayload, as: UTF8.self))
        return await run(prompt: prompt, userPrompt: text, fixedTitle: currentTitle, expectedKind: kind, apiKey: apiKey, model: model)
    }

    /// Turns an answer pasted from an external AI (Claude, ChatGPT) into a draft. No AI call, so no key is needed.
    /// Goes through the same parser, lint, capability filter and spec validation as a Gemini answer. The in-app size setting
    /// is what Gemini is asked to write, so it does not apply here: an external answer may be as big as the person's external cap (up to 2 MB, what storage accepts).
    func importDraft(_ text: String, fixedTitle: String?, expectedKind: ArtifactKind?, userPrompt: String) -> Result<ArtifactDraft, ArtifactGenError> {
        guard text.utf8.count <= ArtifactOutputBudget.externalBytes(forKB: externalMaxKB) + ArtifactImport.chatSlackBytes else { return .failure(.invalidApp("the pasted text is far too large")) }
        var external = self
        external.appByteLimit = ArtifactOutputBudget.externalBytes(forKB: externalMaxKB)
        switch ArtifactEnvelopeParser.parse(ArtifactImport.normalize(text, registry: registry)) {
        case .failure(let error): return .failure(error)
        case .success(let envelope): return external.build(envelope, fixedTitle: fixedTitle, expectedKind: expectedKind, userPrompt: userPrompt)
        }
    }

    /// One attempt, plus at most one retry with the concrete problem appended.
    private func run(prompt: String, userPrompt: String, fixedTitle: String?, expectedKind: ArtifactKind?, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError> {
        var currentPrompt = prompt
        for tryIndex in 0...1 {
            switch await attempt(prompt: currentPrompt, userPrompt: userPrompt, fixedTitle: fixedTitle, expectedKind: expectedKind, apiKey: apiKey, model: model) {
            case .success(let draft):
                return .success(draft)
            case .failure(let error):
                let retryable: Bool
                switch error {
                case .truncated, .invalidSpec, .invalidApp, .malformedEnvelope: retryable = true
                case .ai, .kindNotAvailable, .tooLargeToExtend: retryable = false
                }
                if retryable && tryIndex == 0 {
                    currentPrompt = prompt + "\n\n" + ArtifactPrompts.retryAddendum(for: error)
                    continue
                }
                if expectedKind != nil, case .truncated = error { return .failure(.tooLargeToExtend) }
                return .failure(error)
            }
        }
        return .failure(.malformedEnvelope("no attempt was made")) // unreachable: the loop always returns
    }

    private func attempt(prompt: String, userPrompt: String, fixedTitle: String?, expectedKind: ArtifactKind?, apiKey: String, model: AIModel) async -> Result<ArtifactDraft, ArtifactGenError> {
        let instruction = ArtifactPrompts.systemInstruction(registry: registry, language: language, allowedKinds: allowedKinds, maxKB: maxOutputKB)
        // The output budget travels as a task-local so the AIClient protocol (and every mock) stays as it is.
        let result = await ArtifactOutputBudget.$requestedTokens.withValue(ArtifactOutputBudget.tokens(forKB: maxOutputKB)) {
            await ai.generateJSON(
                prompt: prompt,
                systemInstruction: instruction,
                schema: nil,
                apiKey: apiKey,
                model: model,
                temperature: 0.4
            )
        }
        switch result {
        case .failure(.truncated):
            // The Gemini client reports a hit output cap as `.truncated` and drops the partial text.
            return .failure(.truncated)
        case .failure(let error):
            return .failure(.ai(error))
        case .success(let text):
            switch ArtifactEnvelopeParser.parse(text) {
            case .failure(let error):
                return .failure(error)
            case .success(let envelope):
                return build(envelope, fixedTitle: fixedTitle, expectedKind: expectedKind, userPrompt: userPrompt)
            }
        }
    }

    private func build(_ envelope: ArtifactEnvelope, fixedTitle: String?, expectedKind: ArtifactKind?, userPrompt: String) -> Result<ArtifactDraft, ArtifactGenError> {
        guard allowedKinds.contains(envelope.kind) else { return .failure(.kindNotAvailable) }
        // An update keeps the artifact's kind; the AI switching kinds is a format slip worth one retry.
        if let expectedKind, envelope.kind != expectedKind {
            return .failure(.malformedEnvelope("the kind must stay \"\(expectedKind.rawValue)\""))
        }
        switch envelope.kind {
        case .spec: return buildSpec(envelope, fixedTitle: fixedTitle, userPrompt: userPrompt)
        case .app: return buildApp(envelope, fixedTitle: fixedTitle, userPrompt: userPrompt)
        }
    }

    private func buildApp(_ envelope: ArtifactEnvelope, fixedTitle: String?, userPrompt: String) -> Result<ArtifactDraft, ArtifactGenError> {
        switch ArtifactHTMLLint.check(envelope.payload, maxBytes: allowedAppBytes) {
        case .failure(.tooLarge):
            // The retry names the real limit (the person's setting, or 2 MB for a pasted answer), not a vague "smaller".
            return .failure(.invalidApp("the HTML is larger than \(Self.describeSize(allowedAppBytes)); make it much smaller"))
        case .failure(let error):
            return .failure(.invalidApp(error.detail))
        case .success(let html):
            // Only registered capabilities survive; storage.* needs no request but is harmless.
            let requests = Set(envelope.requests).filter { registry.capability(named: $0) != nil }.sorted()
            return .success(ArtifactDraft(kind: .app, title: fixedTitle ?? envelope.title, payload: Data(html.utf8), requests: requests, prompt: userPrompt))
        }
    }

    private func buildSpec(_ envelope: ArtifactEnvelope, fixedTitle: String?, userPrompt: String) -> Result<ArtifactDraft, ArtifactGenError> {
        let spec: ArtifactSpec
        switch SpecValidator.decode(envelope.payload) {
        case .failure(let error): return .failure(.invalidSpec(Self.describe(error)))
        case .success(let decoded): spec = decoded
        }
        switch SpecValidator.validate(spec, requests: envelope.requests, registry: registry) {
        case .failure(let error):
            return .failure(.invalidSpec(Self.describe(error)))
        case .success(let valid):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let payload = try? encoder.encode(valid.spec) else { return .failure(.invalidSpec("the spec could not be encoded")) }
            return .success(ArtifactDraft(kind: .spec, title: fixedTitle ?? envelope.title, payload: payload, requests: valid.requests, prompt: userPrompt))
        }
    }

    /// "20 KB" or "2 MB".
    static func describeSize(_ bytes: Int) -> String {
        bytes >= 1_048_576 && bytes % 1_048_576 == 0 ? "\(bytes / 1_048_576) MB" : "\(bytes / 1024) KB"
    }

    private static func describe(_ error: SpecValidationError) -> String {
        switch error {
        case .empty: return "the spec has no usable blocks"
        case .malformed(let detail): return detail
        }
    }
}
