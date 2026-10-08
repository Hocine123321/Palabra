import Foundation
import SwiftData

/// Lifecycle of a flagged word. Raw values are persisted: append-only.
enum ReviewStatus: String {
    case open
    case cleared
}

/// A word the person should review again. `headword` and `translation` are snapshots so this
/// feature never needs `Word`. Referenced by plain UUID (no @Relationship). New SwiftData entity:
/// stored property names are append-only once shipped.
@Model
final class ReviewNeed {
    @Attribute(.unique) var id: UUID
    var wordID: UUID
    var headword: String
    var translation: String
    var score: Double
    var note: String
    var sourceArtifactID: UUID?
    var flagCount: Int
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var clearedAt: Date?

    init(wordID: UUID, headword: String, translation: String, score: Double, note: String, sourceArtifactID: UUID?, now: Date) {
        id = UUID()
        self.wordID = wordID
        self.headword = headword
        self.translation = translation
        self.score = score
        self.note = note
        self.sourceArtifactID = sourceArtifactID
        flagCount = 1
        statusRaw = ReviewStatus.open.rawValue
        createdAt = now
        updatedAt = now
        clearedAt = nil
    }

    var status: ReviewStatus {
        get { ReviewStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
}
