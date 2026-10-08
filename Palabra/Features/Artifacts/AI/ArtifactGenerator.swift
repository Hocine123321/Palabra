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
        let result = await ai.generateJSON(
            prompt: prompt,
            systemInstruction: ArtifactPrompts.systemInstruction(registry: registry, language: language, allowedKinds: allowedKinds),
            schema: nil,
            apiKey: apiKey,
            model: model,
            temperature: 0.4
        )
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
        switch ArtifactHTMLLint.check(envelope.payload) {
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

    private static func describe(_ error: SpecValidationError) -> String {
        switch error {
        case .empty: return "the spec has no usable blocks"
        case .malformed(let detail): return detail
        }
    }
}
