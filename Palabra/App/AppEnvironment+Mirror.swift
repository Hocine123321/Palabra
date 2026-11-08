import Foundation

/// Mirroring's link to the rest of the app. `Features/Mirroring` never imports `Word`: this is where words become records.
extension AppEnvironment {
    /// Every library word as a mirror record. Never includes pronunciation audio, the old chat or the raw AI response.
    func mirrorWordRecords() -> [MirrorRecord] {
        let formatter = ISO8601DateFormatter()
        return repository.allWords().map { word in
            let content = (try? JSONEncoder().encode(word.content)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
            let payload: JSONValue = .object([
                "id": .string(word.id.uuidString),
                "key": .string(word.key),
                "spanish": .string(word.spanish),
                "translation": .string(word.translation),
                "partOfSpeech": .string(word.partOfSpeech),
                "category": word.category.map { JSONValue.string($0) } ?? .null,
                "tags": .array(word.tags.map { JSONValue.string($0) }),
                "createdAt": .string(formatter.string(from: word.createdAt)),
                "updatedAt": .string(formatter.string(from: word.updatedAt)),
                "content": content,
            ])
            return MirrorRecord(kind: "word", recordID: word.id.uuidString, payload: payload)
        }
    }
}
