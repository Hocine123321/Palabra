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
    }

    let mode: Mode
    var request = ""
    private(set) var draft: ArtifactDraft?
    private(set) var phase: Phase = .input
    /// Set when saving failed (payload too large, artifact gone); cleared on the next attempt.
    private(set) var saveError: String?

    private let environment: AppEnvironment
    private var lastOperation: Operation = .generate

    init(environment: AppEnvironment, mode: Mode = .create) {
        self.environment = environment
        self.mode = mode
    }

    var canGenerate: Bool {
        request.trimmingCharacters(in: .whitespacesAndNewlines).count >= ArtifactGeneratorLimits.minRequestLength
    }

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
        }
    }

    /// Leaves the failed state: back to the preview if there is a draft, else to the request.
    func dismissFailure() {
        phase = draft == nil ? .input : .preview
    }

    func discard() {
        draft = nil
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
            case .success(let artifact): return artifact.id
            case .failure(let error): saveError = Self.message(for: error); return nil
            }
        case .update(let artifactID):
            switch environment.artifacts.addVersion(artifactID: artifactID, payload: draft.payload, requested: draft.requests, prompt: draft.prompt, now: Date()) {
            case .success: return artifactID
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
        let generator = ArtifactGenerator(ai: environment.ai, registry: environment.capabilities, language: environment.aiLanguage)
        let result: Result<ArtifactDraft, ArtifactGenError>
        switch operation {
        case .generate:
            switch mode {
            case .create:
                result = await generator.create(request: request, apiKey: key, model: model)
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
        }
        switch result {
        case .success(let value):
            draft = value
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
