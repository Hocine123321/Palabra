import Foundation
import SwiftData

enum ArtifactLimits {
    /// What storage accepts: the largest an external AI may write (2 MB). The in-app AI is held to its own, smaller setting.
    static let maxPayloadBytes = ArtifactOutputBudget.storageMaxBytes
    static let maxVersions = 20
    static let maxStateBytes = 262_144
    static let maxStateKeyLength = 64
}

enum ArtifactStorageError: Error, Equatable {
    case payloadTooLarge
    case storageFull
    case keyTooLong
    case notFound
}

/// Hides SwiftData behind a small protocol, like `WordRepository` and `CardRepository`.
@MainActor
protocol ArtifactRepository {
    /// Most recently updated first.
    func artifacts() -> [Artifact]
    func artifact(id: UUID) -> Artifact?
    /// Newest first.
    func versions(artifactID: UUID) -> [ArtifactVersion]
    func create(title: String, kind: ArtifactKind, payload: Data, requested: [String], prompt: String, now: Date) -> Result<Artifact, ArtifactStorageError>
    /// Bumps `currentVersion`, touches `updatedAt`, keeps only the newest `maxVersions`.
    func addVersion(artifactID: UUID, payload: Data, requested: [String], prompt: String, now: Date) -> Result<ArtifactVersion, ArtifactStorageError>
    /// History is append-only: copies an old version into a new one.
    func restore(artifactID: UUID, versionNumber: Int, now: Date) -> Result<ArtifactVersion, ArtifactStorageError>
    /// Removes the artifact, its versions and its state.
    func delete(id: UUID)
    /// Replaces the approved capability names (sorted, unique). No-op for an unknown artifact.
    func setGranted(artifactID: UUID, names: [String])
    func stateValue(artifactID: UUID, key: String) -> Data?
    func setStateValue(artifactID: UUID, key: String, value: Data) -> Result<Void, ArtifactStorageError>
    func removeStateValue(artifactID: UUID, key: String)
}

@MainActor
final class SwiftDataArtifactRepository: ArtifactRepository {
    private let context: ModelContext
    /// Keeps an in-memory container alive when this repository owns it.
    private let retainedContainer: ModelContainer?
    /// The readable copy of every artifact in the Storage page. `nil` in tests and previews, which must not touch real folders.
    private let mirror: ArtifactFileMirror?

    init(context: ModelContext, retaining container: ModelContainer? = nil, mirror: ArtifactFileMirror? = nil) {
        self.context = context
        self.retainedContainer = container
        self.mirror = mirror
    }

    /// Writes the artifact's files (one per kept version) from what the database holds now. Never fails a save.
    private func mirrorArtifact(_ id: UUID) {
        guard let mirror, let artifact = artifact(id: id) else { return }
        let kept = versions(artifactID: id).map { (number: $0.number, payload: $0.payload) }
        mirror.sync(id: id, title: artifact.title, kind: artifact.kind, versions: kept)
    }

    /// Brings the whole folder in line with the database: files for artifacts saved before the folder existed (or deleted from it by
    /// hand), and no folders for artifacts that are gone. Call once at launch.
    func syncMirror() {
        guard let mirror else { return }
        let all = artifacts()
        for artifact in all { mirrorArtifact(artifact.id) }
        mirror.prune(keeping: Set(all.map(\.id)))
    }

    /// A private in-memory store: the default for tests and previews that don't care about artifacts.
    static func inMemory() -> SwiftDataArtifactRepository {
        let schema = Schema([Artifact.self, ArtifactVersion.self, ArtifactStateEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataArtifactRepository(context: ModelContext(container), retaining: container)
    }

    func artifacts() -> [Artifact] {
        let descriptor = FetchDescriptor<Artifact>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func artifact(id: UUID) -> Artifact? {
        let descriptor = FetchDescriptor<Artifact>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func versions(artifactID: UUID) -> [ArtifactVersion] {
        let descriptor = FetchDescriptor<ArtifactVersion>(
            predicate: #Predicate { $0.artifactID == artifactID },
            sortBy: [SortDescriptor(\.number, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func create(title: String, kind: ArtifactKind, payload: Data, requested: [String], prompt: String, now: Date) -> Result<Artifact, ArtifactStorageError> {
        guard payload.count <= ArtifactLimits.maxPayloadBytes else { return .failure(.payloadTooLarge) }
        let artifact = Artifact(title: title, kind: kind, now: now)
        context.insert(artifact)
        context.insert(ArtifactVersion(artifactID: artifact.id, number: 1, payload: payload, requested: requested, prompt: prompt, createdAt: now))
        Persistence.save(context)
        mirrorArtifact(artifact.id)
        return .success(artifact)
    }

    func addVersion(artifactID: UUID, payload: Data, requested: [String], prompt: String, now: Date) -> Result<ArtifactVersion, ArtifactStorageError> {
        guard let artifact = artifact(id: artifactID) else { return .failure(.notFound) }
        guard payload.count <= ArtifactLimits.maxPayloadBytes else { return .failure(.payloadTooLarge) }
        let number = artifact.currentVersion + 1
        let version = ArtifactVersion(artifactID: artifactID, number: number, payload: payload, requested: requested, prompt: prompt, createdAt: now)
        context.insert(version)
        artifact.currentVersion = number
        artifact.updatedAt = now
        // Save first so the prune fetch certainly sees the new version.
        Persistence.save(context)
        // Newest first; everything past `maxVersions` is pruned.
        for old in versions(artifactID: artifactID).dropFirst(ArtifactLimits.maxVersions) {
            context.delete(old)
        }
        Persistence.save(context)
        mirrorArtifact(artifactID)
        return .success(version)
    }

    func restore(artifactID: UUID, versionNumber: Int, now: Date) -> Result<ArtifactVersion, ArtifactStorageError> {
        guard let source = versions(artifactID: artifactID).first(where: { $0.number == versionNumber }) else {
            return .failure(.notFound)
        }
        return addVersion(
            artifactID: artifactID,
            payload: source.payload,
            requested: source.requestedNames,
            prompt: "Restored version \(versionNumber)",
            now: now
        )
    }

    func setGranted(artifactID: UUID, names: [String]) {
        guard let artifact = artifact(id: artifactID) else { return }
        artifact.grantedNames = Array(Set(names)).sorted()
        Persistence.save(context)
    }

    func delete(id: UUID) {
        for version in versions(artifactID: id) { context.delete(version) }
        for entry in stateEntries(artifactID: id) { context.delete(entry) }
        if let artifact = artifact(id: id) { context.delete(artifact) }
        Persistence.save(context)
        mirror?.remove(id: id)
    }

    func stateValue(artifactID: UUID, key: String) -> Data? {
        stateEntries(artifactID: artifactID).first { $0.key == key }?.valueData
    }

    func setStateValue(artifactID: UUID, key: String, value: Data) -> Result<Void, ArtifactStorageError> {
        guard key.count <= ArtifactLimits.maxStateKeyLength else { return .failure(.keyTooLong) }
        let entries = stateEntries(artifactID: artifactID)
        let existing = entries.first { $0.key == key }
        // Overwriting a key swaps its size instead of adding to it.
        let others = entries.reduce(0) { $0 + $1.valueData.count } - (existing?.valueData.count ?? 0)
        guard others + value.count <= ArtifactLimits.maxStateBytes else { return .failure(.storageFull) }
        if let existing {
            existing.valueData = value
            existing.updatedAt = Date()
        } else {
            context.insert(ArtifactStateEntry(artifactID: artifactID, key: key, valueData: value))
        }
        Persistence.save(context)
        return .success(())
    }

    func removeStateValue(artifactID: UUID, key: String) {
        guard let entry = stateEntries(artifactID: artifactID).first(where: { $0.key == key }) else { return }
        context.delete(entry)
        Persistence.save(context)
    }

    private func stateEntries(artifactID: UUID) -> [ArtifactStateEntry] {
        let descriptor = FetchDescriptor<ArtifactStateEntry>(predicate: #Predicate { $0.artifactID == artifactID })
        return (try? context.fetch(descriptor)) ?? []
    }
}
