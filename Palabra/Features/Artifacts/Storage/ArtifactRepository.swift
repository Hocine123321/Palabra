import Foundation
import SwiftData

enum ArtifactLimits {
    static let maxPayloadBytes = 65_536
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
    func stateValue(artifactID: UUID, key: String) -> Data?
    func setStateValue(artifactID: UUID, key: String, value: Data) -> Result<Void, ArtifactStorageError>
    func removeStateValue(artifactID: UUID, key: String)
}

@MainActor
final class SwiftDataArtifactRepository: ArtifactRepository {
    private let context: ModelContext
    /// Keeps an in-memory container alive when this repository owns it.
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
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
        try? context.save()
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
        try? context.save()
        // Newest first; everything past `maxVersions` is pruned.
        for old in versions(artifactID: artifactID).dropFirst(ArtifactLimits.maxVersions) {
            context.delete(old)
        }
        try? context.save()
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

    func delete(id: UUID) {
        for version in versions(artifactID: id) { context.delete(version) }
        for entry in stateEntries(artifactID: id) { context.delete(entry) }
        if let artifact = artifact(id: id) { context.delete(artifact) }
        try? context.save()
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
        try? context.save()
        return .success(())
    }

    func removeStateValue(artifactID: UUID, key: String) {
        guard let entry = stateEntries(artifactID: artifactID).first(where: { $0.key == key }) else { return }
        context.delete(entry)
        try? context.save()
    }

    private func stateEntries(artifactID: UUID) -> [ArtifactStateEntry] {
        let descriptor = FetchDescriptor<ArtifactStateEntry>(predicate: #Predicate { $0.artifactID == artifactID })
        return (try? context.fetch(descriptor)) ?? []
    }
}
