import Foundation

/// The text of a library backup: stored (compressed, as a binary property list) in the archive file's metadata block.
/// The pronunciation clips are not in here; each word points at its clip inside the same file.
/// New fields must be optional, so a backup made by an older version keeps reading.
struct LibraryArchive: Codable, Equatable, Sendable {
    static let formatName = "Palabra Library"
    static let currentVersion = 1

    var format: String
    var version: Int
    var createdAt: Date
    var appVersion: String?
    var words: [WordBackup]
    var study: StudyBackup?
    var chats: [ChatBackup]?

    init(createdAt: Date, appVersion: String?, words: [WordBackup], study: StudyBackup?, chats: [ChatBackup]?) {
        format = Self.formatName
        version = Self.currentVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.words = words
        self.study = study
        self.chats = chats
    }
}
