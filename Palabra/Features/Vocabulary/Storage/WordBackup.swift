import Foundation

/// One word as it travels in a backup: everything the person has, as plain values.
/// New fields must be optional, so a backup made by an older version keeps reading.
struct WordBackup: Codable, Equatable, Sendable {
    var id: UUID
    var content: WordContent
    var createdAt: Date
    var updatedAt: Date
    /// The library section and the tags (the organization).
    var category: String?
    var tags: [String]?
    /// The old per-word chat (newer chats are saved separately, see `ChatBackup`).
    var chat: [ChatMessage]?
    /// The pronunciation clip (TTS audio), stored once in the archive file.
    var audio: ArchiveBlobRef?
}

/// What restoring a list of words did.
struct WordRestoreResult: Equatable, Sendable {
    /// New words added.
    var imported = 0
    /// Words already in the library that gained something they lacked (a section, tags, a pronunciation clip).
    var updated = 0
    /// Words already in the library with nothing to add.
    var skipped = 0
    /// Entries that could not be used (no headword).
    var invalid = 0
    var clipsRestored = 0
    /// Backup id -> the id the word has in this library (the same, unless the word was already here under another id).
    var idMap: [UUID: UUID] = [:]

    mutating func add(_ other: WordRestoreResult) {
        imported += other.imported
        updated += other.updated
        skipped += other.skipped
        invalid += other.invalid
        clipsRestored += other.clipsRestored
        idMap.merge(other.idMap) { first, _ in first }
    }
}
