import Foundation

/// One saved assistant conversation as plain values, for a backup.
struct ChatBackup: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    /// The word the chat was opened from, if any.
    var wordID: UUID?
    var turns: [ChatTurn]
    var createdAt: Date
    var updatedAt: Date
}
