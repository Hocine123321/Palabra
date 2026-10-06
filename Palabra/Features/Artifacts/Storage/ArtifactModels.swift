import Foundation
import SwiftData

/// A saved artifact. New SwiftData entities; stored property names and raw values are
/// append-only once shipped. Versions and state are referenced by plain UUID (no @Relationship).
@Model
final class Artifact {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var currentVersion: Int
    /// JSON `[String]` of capability names the user approved.
    var grantedData: Data
    var createdAt: Date
    var updatedAt: Date

    init(title: String, kind: ArtifactKind, now: Date = Date()) {
        id = UUID()
        self.title = title
        kindRaw = kind.rawValue
        currentVersion = 1
        grantedData = Data("[]".utf8)
        createdAt = now
        updatedAt = now
    }

    var kind: ArtifactKind {
        get { ArtifactKind(rawValue: kindRaw) ?? .spec }
        set { kindRaw = newValue.rawValue }
    }

    var grantedNames: [String] {
        get { (try? JSONDecoder().decode([String].self, from: grantedData)) ?? [] }
        set { grantedData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}

/// One immutable snapshot of an artifact's payload (spec JSON, or UTF-8 HTML for apps).
@Model
final class ArtifactVersion {
    @Attribute(.unique) var id: UUID
    var artifactID: UUID
    var number: Int
    var payload: Data
    /// JSON `[String]` manifest of capabilities this version asks for.
    var requestedData: Data
    var prompt: String
    var createdAt: Date

    init(artifactID: UUID, number: Int, payload: Data, requested: [String], prompt: String, createdAt: Date) {
        id = UUID()
        self.artifactID = artifactID
        self.number = number
        self.payload = payload
        requestedData = (try? JSONEncoder().encode(requested)) ?? Data("[]".utf8)
        self.prompt = prompt
        self.createdAt = createdAt
    }

    var requestedNames: [String] {
        (try? JSONDecoder().decode([String].self, from: requestedData)) ?? []
    }
}

/// Per-artifact key/value storage behind `storage.*` and spec tick state.
@Model
final class ArtifactStateEntry {
    var artifactID: UUID
    var key: String
    var valueData: Data
    var updatedAt: Date

    init(artifactID: UUID, key: String, valueData: Data, updatedAt: Date = Date()) {
        self.artifactID = artifactID
        self.key = key
        self.valueData = valueData
        self.updatedAt = updatedAt
    }
}
