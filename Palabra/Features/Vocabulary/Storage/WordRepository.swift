import Foundation
import SwiftData

/// The few fields the library-wide jobs need (card sync, orphan cleanup, section names), so they do not load every
/// word with its audio, raw JSON and chat.
struct WordSummary: Equatable, Sendable {
    let id: UUID
    let spanish: String
    let translation: String
    let category: String?
}

struct ImportResult: Equatable {
    var imported: Int
    var skipped: Int
}

/// Hides SwiftData behind a small protocol so features depend on this, not
/// `ModelContext` directly.
@MainActor
protocol WordRepository {
    func find(key: String) -> Word?
    /// One word by id. Prefer this over `allWords().first { ... }`, which loads every word (and its audio).
    func word(id: UUID) -> Word?
    /// Newest first, like `allWords()`, but only the fields in `WordSummary` are fetched.
    func wordSummaries() -> [WordSummary]
    /// How many words are saved, counted in the store without loading them.
    func wordCount() -> Int
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

    func word(id: UUID) -> Word? { fetchByID(id) }

    func wordCount() -> Int { (try? context.fetchCount(FetchDescriptor<Word>())) ?? 0 }

    func wordSummaries() -> [WordSummary] {
        var descriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        // A partial fetch: anything not listed is loaded on first access, so this is only ever an optimisation.
        descriptor.propertiesToFetch = [\.id, \.spanish, \.translation, \.category]
        let words = (try? context.fetch(descriptor)) ?? []
        return words.map { WordSummary(id: $0.id, spanish: $0.spanish, translation: $0.translation, category: $0.category) }
    }

    @discardableResult
    func insert(spanish: String, key: String, searchKey: String, content: WordContent, rawJSON: Data) -> Word {
        let word = Word(spanish: spanish, key: key, searchKey: searchKey, content: content, rawJSON: rawJSON)
        context.insert(word)
        Persistence.save(context)
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
        Persistence.save(context)
    }

    func updateChat(id: UUID, messages: [ChatMessage]) {
        guard let word = fetchByID(id) else { return }
        word.chat = messages
        Persistence.save(context)
    }

    func updatePronunciation(id: UUID, audio: Data?) {
        guard let word = fetchByID(id) else { return }
        word.pronunciationAudio = audio
        Persistence.save(context)
    }

    func updatePlacement(id: UUID, category: String?, tags: [String]) {
        guard let word = fetchByID(id) else { return }
        word.category = category
        word.tags = tags
        Persistence.save(context)
    }

    func updatePlacements(_ placements: [UUID: WordPlacement]) {
        for word in allWords() {
            guard let placement = placements[word.id] else { continue }
            word.category = placement.category
            word.tags = placement.tags
        }
        Persistence.save(context)
    }

    func clearAllPlacements() {
        for word in allWords() {
            word.category = nil
            word.tags = []
        }
        Persistence.save(context)
    }

    func delete(id: UUID) {
        guard let word = fetchByID(id) else { return }
        context.delete(word)
        Persistence.save(context)
    }

    func deleteAll() {
        for word in allWords() { context.delete(word) }
        Persistence.save(context)
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
            // A hand-edited or damaged file can carry a blank headword; it would become an unreachable, unnamed word.
            guard !key.isEmpty, find(key: key) == nil else {
                skipped += 1
                continue
            }
            let word = Word(spanish: item.content.word, key: key, searchKey: WordKey.search(item.content.word), content: item.content, rawJSON: item.raw, createdAt: item.createdAt)
            word.updatedAt = item.updatedAt
            word.chat = item.chat
            context.insert(word)
            imported += 1
        }
        // Never report words as imported when they are not on disk.
        guard Persistence.save(context) else {
            context.rollback()
            throw VocabularyLibraryExporter.ExportError.saveFailed
        }
        return ImportResult(imported: imported, skipped: skipped)
    }

    private func fetchByID(_ id: UUID) -> Word? {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
