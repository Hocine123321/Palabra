import Foundation

/// How an artifact is rendered. Persisted by raw value: append-only once shipped.
enum ArtifactKind: String, Codable, Sendable {
    /// Declarative blocks rendered natively (tables, charts, roadmaps, checklists).
    case spec
    /// A sandboxed single-file web app (arrives with plan B2).
    case app
}
