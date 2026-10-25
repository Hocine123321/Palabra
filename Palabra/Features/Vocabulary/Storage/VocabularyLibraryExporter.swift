import Foundation

/// The OLD export format: one JSON file with the words (base64 for any binary data). It is no longer written, because
/// the file grew too large; it is only read, so an export made by an earlier version still imports.
/// The current format is `LibraryArchive` in an `ArchiveContainer` file (see `LibraryBackupService`).
enum VocabularyLibraryExporter {
    struct Envelope: Codable {
        var app: String
        var version: Int
        var exportedAt: Date
        var words: [Item]
    }

    struct Item: Codable {
        var content: WordContent
        var raw: Data
        var createdAt: Date
        var updatedAt: Date
        var chat: [ChatMessage]
    }

    enum ExportError: Error, Equatable {
        case unsupportedVersion(Int)
        case malformed
    }

    static let currentVersion = 1

    /// Only used by tests, to build an old-format file.
    static func encode(items: [Item], exportedAt: Date = Date()) throws -> Data {
        let envelope = Envelope(app: "Palabra", version: currentVersion, exportedAt: exportedAt, words: items)
        guard let data = try? JSONEncoder().encode(envelope), !data.isEmpty else { throw ExportError.malformed }
        return data
    }

    static func decode(_ data: Data) throws -> Envelope {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ExportError.malformed
        }
        guard envelope.version == currentVersion else {
            throw ExportError.unsupportedVersion(envelope.version)
        }
        return envelope
    }

    /// An old export as backup records (new ids, no audio, no organization: the old format never carried them).
    static func records(from envelope: Envelope) -> [WordBackup] {
        envelope.words.map {
            WordBackup(id: UUID(), content: $0.content, createdAt: $0.createdAt, updatedAt: $0.updatedAt, category: nil, tags: nil, chat: $0.chat.isEmpty ? nil : $0.chat, audio: nil)
        }
    }
}
