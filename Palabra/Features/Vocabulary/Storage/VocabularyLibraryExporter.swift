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
    }

    static let currentVersion = 1

    static func encode(items: [Item], exportedAt: Date = Date()) -> Data {
        let envelope = Envelope(app: "Palabra", version: currentVersion, exportedAt: exportedAt, words: items)
        return (try? JSONEncoder().encode(envelope)) ?? Data()
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
