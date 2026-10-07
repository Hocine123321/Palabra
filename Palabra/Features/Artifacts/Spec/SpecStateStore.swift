import Foundation

/// Remembers which checklist items / roadmap steps are done, keyed by the block's id.
@MainActor
protocol SpecStateStore: AnyObject {
    func completed(blockID: String) -> Set<Int>
    func setCompleted(blockID: String, _ indices: Set<Int>)
}

/// For drafts and previews: nothing is persisted.
@MainActor
final class InMemorySpecStateStore: SpecStateStore {
    private var values: [String: Set<Int>] = [:]

    func completed(blockID: String) -> Set<Int> { values[blockID] ?? [] }
    func setCompleted(blockID: String, _ indices: Set<Int>) { values[blockID] = indices }
}

/// Persists ticks in the artifact's own state (`spec.<blockID>` -> JSON `[Int]`).
/// A write that would exceed the state limit is ignored, never a crash.
@MainActor
final class ArtifactSpecStateStore: SpecStateStore {
    private let artifactID: UUID
    private let repository: ArtifactRepository

    init(artifactID: UUID, repository: ArtifactRepository) {
        self.artifactID = artifactID
        self.repository = repository
    }

    private func key(_ blockID: String) -> String { "spec.\(blockID)" }

    func completed(blockID: String) -> Set<Int> {
        guard let data = repository.stateValue(artifactID: artifactID, key: key(blockID)),
              let list = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(list)
    }

    func setCompleted(blockID: String, _ indices: Set<Int>) {
        guard let data = try? JSONEncoder().encode(indices.sorted()) else { return }
        _ = repository.setStateValue(artifactID: artifactID, key: key(blockID), value: data)
    }
}
