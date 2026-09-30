import Foundation
import SwiftData

struct ImportResult: Equatable {
    var imported: Int
    var skipped: Int
}

/// Hides SwiftData behind a small protocol so features depend on this, not
/// `ModelContext` directly.
@MainActor
protocol WordRepository {
    func find(key: String) -> Word?
    @discardableResult
    func insert(spanish: String, key: String, searchKey: String, content: WordContent, rawJSON: Data) -> Word
    func replaceContent(id: UUID, content: WordContent, rawJSON: Data)
    func updateChat(id: UUID, messages: [ChatMessage])
    func updatePronunciation(id: UUID, audio: Data?)
    /// Sets a word's section and tags. `nil` category clears the placement.
    func updatePlacement(id: UUID, category: String?, tags: [String])
    func updatePlacements(_ placements: [UUID: WordPlacement])
    /// Removes every word's section and tags (words themselves are untouched).
    func clearAllPlacements()
    func delete(id: UUID)
    func deleteAll()
    func allWords() -> [Word]
    func exportData() -> Data
    func importData(_ data: Data) throws -> ImportResult
}

@MainActor
final class SwiftDataWordRepository: WordRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func find(key: String) -> Word? {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.key == key })
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func insert(spanish: String, key: String, searchKey: String, content: WordContent, rawJSON: Data) -> Word {
        let word = Word(spanish: spanish, key: key, searchKey: searchKey, content: content, rawJSON: rawJSON)
        context.insert(word)
        try? context.save()
        return word
    }

    func replaceContent(id: UUID, content: WordContent, rawJSON: Data) {
        guard let word = fetchByID(id) else { return }
        word.content = content
        word.rawJSON = rawJSON
        word.updatedAt = Date()
        // The corrected headword can change on regeneration, so any cached
        // pronunciation would be for the wrong word — clear it and let the
        // caller re-trigger synthesis for the new content.
        word.pronunciationAudio = nil
        try? context.save()
    }

    func updateChat(id: UUID, messages: [ChatMessage]) {
        guard let word = fetchByID(id) else { return }
        word.chat = messages
        try? context.save()
    }

    func updatePronunciation(id: UUID, audio: Data?) {
        guard let word = fetchByID(id) else { return }
        word.pronunciationAudio = audio
        try? context.save()
    }

    func updatePlacement(id: UUID, category: String?, tags: [String]) {
        guard let word = fetchByID(id) else { return }
        word.category = category
        word.tags = tags
        try? context.save()
    }

    func updatePlacements(_ placements: [UUID: WordPlacement]) {
        for word in allWords() {
            guard let placement = placements[word.id] else { continue }
            word.category = placement.category
            word.tags = placement.tags
        }
        try? context.save()
    }

    func clearAllPlacements() {
        for word in allWords() {
            word.category = nil
            word.tags = []
        }
        try? context.save()
    }

    func delete(id: UUID) {
        guard let word = fetchByID(id) else { return }
        context.delete(word)
        try? context.save()
    }

    func deleteAll() {
        for word in allWords() { context.delete(word) }
        try? context.save()
    }

    func allWords() -> [Word] {
        let descriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func exportData() -> Data {
        let items = allWords().map {
            VocabularyLibraryExporter.Item(content: $0.content, raw: $0.rawJSON, createdAt: $0.createdAt, updatedAt: $0.updatedAt, chat: $0.chat)
        }
        return VocabularyLibraryExporter.encode(items: items)
    }

    func importData(_ data: Data) throws -> ImportResult {
        let envelope = try VocabularyLibraryExporter.decode(data)
        var imported = 0
        var skipped = 0
        for item in envelope.words {
            let key = WordKey.identity(item.content.word)
            guard find(key: key) == nil else {
                skipped += 1
                continue
            }
            let word = Word(spanish: item.content.word, key: key, searchKey: WordKey.search(item.content.word), content: item.content, rawJSON: item.raw, createdAt: item.createdAt)
            word.updatedAt = item.updatedAt
            word.chat = item.chat
            context.insert(word)
            imported += 1
        }
        try? context.save()
        return ImportResult(imported: imported, skipped: skipped)
    }

    private func fetchByID(_ id: UUID) -> Word? {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
