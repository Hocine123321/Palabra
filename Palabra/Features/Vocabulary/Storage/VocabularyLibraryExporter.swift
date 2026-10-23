import Foundation

/// Pure JSON envelope for Settings > Data > Export/Import. Kept independent
/// of SwiftData so it can be unit tested without a `ModelContainer`.
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
        /// The words were read but could not be written to the store.
        case saveFailed
        /// The library could not be turned into a file.
        case encodingFailed
    }

    static let currentVersion = 1

    /// Throws instead of returning empty data: an empty file named `.json` would look like a successful backup.
    static func encode(items: [Item], exportedAt: Date = Date()) throws -> Data {
        let envelope = Envelope(app: "Palabra", version: currentVersion, exportedAt: exportedAt, words: items)
        guard let data = try? JSONEncoder().encode(envelope), !data.isEmpty else { throw ExportError.encodingFailed }
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
}
