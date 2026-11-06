import Foundation
import Observation

/// Drives "ask the AI for an artifact": request -> AI -> preview (live, dry-run) -> save.
/// Nothing is persisted until `save()`. Key/model/repair handling mirrors `NotesDeckModel`.
@MainActor
@Observable
final class ArtifactDraftModel {
    enum Mode: Equatable {
        case create
        case update(artifactID: UUID)
    }

    enum Phase: Equatable {
        case input
        case generating
        case preview
        case failed(ArtifactGenError)
    }

    private enum Operation {
        case generate
        case refine(String)
        /// Text pasted from an external AI; replaying it makes no AI call.
        case importExternal(String)
    }

    /// What the editor accepts: the generator's cap minus room for the format line.
    static let maxInput = ArtifactGeneratorLimits.maxRequestLength - 150

    let mode: Mode
    var request = ""
    /// Create mode only: what the person wants to get. `auto` leaves the choice to the AI.
    var format: ArtifactFormat = .auto
    private(set) var draft: ArtifactDraft?
    private(set) var phase: Phase = .input
    /// Set when saving failed (payload too large, artifact gone); cleared on the next attempt.
    private(set) var saveError: String?

    /// Capabilities the person allowed in this draft (on top of what the artifact already had).
    private(set) var approved: Set<String> = []
    /// Whether the person answered the approval card for the current draft.
    private(set) var decided = false

    private let environment: AppEnvironment
    private var lastOperation: Operation = .generate

    init(environment: AppEnvironment, mode: Mode = .create) {
        self.environment = environment
        self.mode = mode
        if case .create = mode {
            switch environment.artifactSettings.defaultFormat {
            case .auto: format = .auto
            case .page: format = .page
            case .app: format = environment.artifactSettings.allowAppArtifacts ? .app : .auto
            }
        }
    }

    // MARK: Approval

    /// Grants the artifact already has (update mode); a new artifact has none.
    private var baseGrants: Set<String> {
        guard case .update(let artifactID) = mode else { return [] }
        return Set(environment.artifacts.artifact(id: artifactID)?.grantedNames ?? [])
    }

    /// What the draft still needs approval for: only the delta on an update.
    var pending: [Capability] {
        guard let draft else { return [] }
        return ArtifactApproval.pending(kind: draft.kind, requested: draft.requests, granted: baseGrants.union(approved), registry: environment.capabilities)
    }

    var needsDecision: Bool { !pending.isEmpty && !decided }

    /// What the preview may actually call.
    var effectiveGrant: Set<String> {
        guard let draft else { return [] }
        return ArtifactApproval.effective(kind: draft.kind, requested: draft.requests, granted: baseGrants.union(approved), registry: environment.capabilities)
    }

    func allowPending() {
        approved.formUnion(pending.map(\.name))
        decided = true
    }

    func denyPending() { decided = true }

    var canGenerate: Bool {
        request.trimmingCharacters(in: .whitespacesAndNewlines).count >= ArtifactGeneratorLimits.minRequestLength
    }

    // MARK: External AI (Claude, ChatGPT)

    /// The prompt to copy into another AI: a request for one complete HTML page, with the sandbox rules, the capabilities it may call,
    /// and the person's request (on update, the current page too). `nil` until the request is long enough, and for a table-style
    /// ("spec") artifact being updated, which is JSON and not a page another AI can edit. Needs no API key.
    func exportPrompt() -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= ArtifactGeneratorLimits.minRequestLength else { return nil }
        let asked = String(trimmed.prefix(Self.maxInput))
        let userPrompt: String
        switch mode {
        case .create:
            // The format picker (page or app) steers Gemini's JSON; another AI always gets the HTML request as the person typed it.
            userPrompt = asked
        case .update(let artifactID):
            guard let current = currentSnapshot(artifactID), current.kind == .app else { return nil }
            userPrompt = ArtifactPrompts.externalUpdateRequest(change: asked, currentTitle: current.title, currentHTML: String(decoding: current.payload, as: UTF8.self))
        }
        return ArtifactPrompts.exportPrompt(userPrompt: userPrompt, registry: environment.capabilities, language: environment.aiLanguage, maxKB: environment.artifactSettings.externalMaxKB)
    }

    /// Whether the copy-prompt route can work at all: always when creating, and when updating only for an HTML page.
    var canUseExternalAI: Bool {
        switch mode {
        case .create: return true
        case .update(let artifactID): return currentSnapshot(artifactID)?.kind == .app
        }
    }

    /// Turns the other AI's answer into the draft, then shows the usual preview (approval card, Refine, Save). Needs no API key.
    func importExternal(_ text: String) {
        lastOperation = .importExternal(text)
        saveError = nil
        let settings = environment.artifactSettings
        let generator = ArtifactGenerator(
            ai: environment.ai, registry: environment.capabilities, language: environment.aiLanguage,
            allowedKinds: settings.allowAppArtifacts ? [.spec, .app] : [.spec],
            externalMaxKB: settings.externalMaxKB
        )
        let asked = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxInput))
        let label = asked.isEmpty ? Self.importedLabel : asked
        let result: Result<ArtifactDraft, ArtifactGenError>
        switch mode {
        case .create:
            result = generator.importDraft(text, fixedTitle: nil, expectedKind: nil, userPrompt: label)
        case .update(let artifactID):
            guard let current = currentSnapshot(artifactID) else {
                phase = .failed(.malformedEnvelope("The artifact no longer exists."))
                return
            }
            result = generator.importDraft(text, fixedTitle: current.title, expectedKind: current.kind, userPrompt: label)
        }
        switch result {
        case .success(let value):
            draft = value
            if !pending.isEmpty { decided = false }
            phase = .preview
        case .failure(let error):
            phase = .failed(error)
        }
    }

    /// Saved as the version's prompt when the person typed no request before pasting.
    static let importedLabel = "Imported from an external AI"

    func generate() async {
        lastOperation = .generate
        saveError = nil
        await execute(.generate, repaired: false)
    }

    /// Asks for a change to the current draft; the draft stays if the change fails.
    func refine(change: String) async {
        let trimmed = change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft != nil, trimmed.count >= ArtifactGeneratorLimits.minRequestLength else { return }
        lastOperation = .refine(trimmed)
        saveError = nil
        await execute(.refine(trimmed), repaired: false)
    }

    func retry() async {
        switch lastOperation {
        case .generate: await generate()
        case .refine(let change): await refine(change: change)
        case .importExternal(let text): importExternal(text)
        }
    }

    /// Leaves the failed state: back to the preview if there is a draft, else to the request.
    func dismissFailure() {
        phase = draft == nil ? .input : .preview
    }

    func discard() {
        draft = nil
        approved = []
        decided = false
        saveError = nil
        phase = .input
    }

    /// Saves the draft. Returns the artifact's id, or `nil` (with `saveError` set) when it could not be saved.
    func save() -> UUID? {
        guard let draft else { return nil }
        saveError = nil
        switch mode {
        case .create:
            switch environment.artifacts.create(title: draft.title, kind: draft.kind, payload: draft.payload, requested: draft.requests, prompt: draft.prompt, now: Date()) {
            case .success(let artifact):
                if !approved.isEmpty { environment.artifacts.setGranted(artifactID: artifact.id, names: Array(approved)) }
                return artifact.id
            case .failure(let error): saveError = Self.message(for: error); return nil
            }
        case .update(let artifactID):
            let grants = baseGrants.union(approved)
            switch environment.artifacts.addVersion(artifactID: artifactID, payload: draft.payload, requested: draft.requests, prompt: draft.prompt, now: Date()) {
            case .success:
                if !approved.isEmpty { environment.artifacts.setGranted(artifactID: artifactID, names: Array(grants)) }
                return artifactID
            case .failure(let error): saveError = Self.message(for: error); return nil
            }
        }
    }

    private static func message(for error: ArtifactStorageError) -> String {
        switch error {
        case .payloadTooLarge: return "This artifact is too large to save. Ask for a simpler version."
        case .storageFull: return "This artifact's storage is full."
        case .keyTooLong, .notFound: return "The artifact could not be saved."
        }
    }

    // MARK: - Running

    private func credentials(repaired: Bool) async -> Result<(key: String, model: AIModel), AIError> {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else { return .failure(.missingAPIKey) }
        guard let model = environment.selectedModel else {
            if environment.selectedModelID != nil, !repaired, await environment.repairMissingModel() != nil {
                return await credentials(repaired: true)
            }
            return .failure(environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? ""))
        }
        return .success((apiKey, model))
    }

    private func execute(_ operation: Operation, repaired: Bool) async {
        // A pasted answer makes no AI call, so it needs no key, no model and no repair: it never waits in `.generating`.
        if case .importExternal(let text) = operation {
            importExternal(text)
            return
        }
        phase = .generating
        let key: String
        let model: AIModel
        switch await credentials(repaired: false) {
        case .failure(let error):
            phase = .failed(.ai(error))
            return
        case .success(let value):
            key = value.key
            model = value.model
        }
        let artifactSettings = environment.artifactSettings
        let generator = ArtifactGenerator(
            ai: environment.ai, registry: environment.capabilities, language: environment.aiLanguage,
            allowedKinds: artifactSettings.allowAppArtifacts ? [.spec, .app] : [.spec],
            maxOutputKB: artifactSettings.maxOutputKB
        )
        let result: Result<ArtifactDraft, ArtifactGenError>
        switch operation {
        case .generate:
            switch mode {
            case .create:
                let asked = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxInput))
                // The saved prompt is what the person typed, not the format line we put in front of it.
                result = await generator.create(request: format.apply(to: asked), apiKey: key, model: model).map { (draft: ArtifactDraft) -> ArtifactDraft in
                    var kept = draft
                    kept.prompt = asked
                    return kept
                }
            case .update(let artifactID):
                guard let current = currentSnapshot(artifactID) else {
                    phase = .failed(.malformedEnvelope("The artifact no longer exists."))
                    return
                }
                result = await generator.update(kind: current.kind, currentTitle: current.title, currentPayload: current.payload, change: request, apiKey: key, model: model)
            }
        case .refine(let change):
            guard let draft else {
                phase = .input
                return
            }
            result = await generator.update(kind: draft.kind, currentTitle: draft.title, currentPayload: draft.payload, change: change, apiKey: key, model: model)
        case .importExternal:
            return   // handled above, before the key is asked for
        }
        switch result {
        case .success(let value):
            draft = value
            // A refined draft that asks for something new is asked about again; the same ask is not.
            if !pending.isEmpty { decided = false }
            phase = .preview
        case .failure(let error):
            phase = .failed(error)
            if case .ai(.modelUnavailable) = error, !repaired, await environment.repairMissingModel() != nil {
                await execute(operation, repaired: true)
            }
        }
    }

    private func currentSnapshot(_ artifactID: UUID) -> (kind: ArtifactKind, title: String, payload: Data)? {
        guard let artifact = environment.artifacts.artifact(id: artifactID),
              let version = environment.artifacts.versions(artifactID: artifactID).first(where: { $0.number == artifact.currentVersion })
        else { return nil }
        return (artifact.kind, artifact.title, version.payload)
    }
}
