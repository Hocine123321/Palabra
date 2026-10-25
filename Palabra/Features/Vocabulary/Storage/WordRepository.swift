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
    /// The saved clip for a word, or nil. Read from its file; a clip still in the database row (saved by an older
    /// version) is returned too.
    func pronunciation(id: UUID) -> Data?
    func hasPronunciation(id: UUID) -> Bool
    /// Moves up to `limit` clips that are still inside word rows into files. Returns how many moved (0 = nothing left
    /// to move, or no progress), so a caller can loop until it returns 0.
    func migrateLegacyPronunciation(limit: Int) -> Int
    /// Sets a word's section and tags. `nil` category clears the placement.
    func updatePlacement(id: UUID, category: String?, tags: [String])
    func updatePlacements(_ placements: [UUID: WordPlacement])
    /// Removes every word's section and tags (words themselves are untouched).
    func clearAllPlacements()
    /// Writes anything still unsaved (a save that failed earlier is tried again). False means the changes are not on disk.
    func flush() -> Bool
    func delete(id: UUID)
    func deleteAll()
    func allWords() -> [Word]
    /// Every word as plain values for a backup (no audio bytes: read those with `pronunciation(id:)`).
    func backupRecords() -> [WordBackup]
    /// Adds the words that are not in the library, and fills in what a word already here lacks (section, tags, clip, old
    /// chat). Never overwrites anything the person already has. `clip` is asked for only when a clip is needed.
    /// Throws `PersistenceError.saveFailed` (and changes nothing) when the batch cannot be written.
    func restore(_ records: [WordBackup], clip: (WordBackup) -> Data?) throws -> WordRestoreResult
}

@MainActor
final class SwiftDataWordRepository: WordRepository {
    private let context: ModelContext
    private let audio: PronunciationFileStore

    init(context: ModelContext, audio: PronunciationFileStore = .standard()) {
        self.context = context
        self.audio = audio
    }

    func find(key: String) -> Word? {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.key == key })
        return try? context.fetch(descriptor).first
    }

    func word(id: UUID) -> Word? { fetchByID(id) }

    func flush() -> Bool { !context.hasChanges || Persistence.save(context) }

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
        audio.remove(id)
        Persistence.save(context)
    }

    func updateChat(id: UUID, messages: [ChatMessage]) {
        guard let word = fetchByID(id) else { return }
        word.chat = messages
        Persistence.save(context)
    }

    func updatePronunciation(id: UUID, audio clip: Data?) {
        guard let word = fetchByID(id) else { return }
        if let clip {
            store(clip, for: word)
        } else {
            audio.remove(id)
            word.pronunciationAudio = nil
        }
        Persistence.save(context)
    }

    func pronunciation(id: UUID) -> Data? {
        if let data = audio.data(for: id) { return data }
        return fetchByID(id)?.pronunciationAudio
    }

    func hasPronunciation(id: UUID) -> Bool {
        audio.exists(for: id) || fetchByID(id)?.pronunciationAudio != nil
    }

    func migrateLegacyPronunciation(limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        var descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.pronunciationAudio != nil })
        descriptor.fetchLimit = limit
        guard let words = try? context.fetch(descriptor) else { return 0 }
        var moved = 0
        for word in words {
            guard let clip = word.pronunciationAudio, audio.write(clip, for: word.id) else { continue }
            word.pronunciationAudio = nil
            moved += 1
        }
        guard moved > 0 else { return 0 }
        // If the save fails the clips are still in the rows (and the files are just copies): report no progress.
        return Persistence.save(context) ? moved : 0
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
        audio.remove(id)
        Persistence.save(context)
    }

    func deleteAll() {
        for word in allWords() { context.delete(word) }
        audio.removeAll()
        Persistence.save(context)
    }

    func allWords() -> [Word] {
        let descriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func backupRecords() -> [WordBackup] {
        allWords().map { word in
            let tags = word.tags
            let chat = word.chat
            return WordBackup(
                id: word.id, content: word.content, createdAt: word.createdAt, updatedAt: word.updatedAt,
                category: word.category, tags: tags.isEmpty ? nil : tags, chat: chat.isEmpty ? nil : chat, audio: nil
            )
        }
    }

    func restore(_ records: [WordBackup], clip: (WordBackup) -> Data?) throws -> WordRestoreResult {
        var result = WordRestoreResult()
        // Every word that got a clip file here, so a failed save leaves no stray files behind.
        var clipIDs: [UUID] = []
        var keysThisBatch = Set<String>()
        var idsThisBatch = Set<UUID>()
        for record in records {
            // Clip, never reject: an old or slightly odd backup still comes in, a damaged one cannot bring huge text.
            let content = ContentValidator.clipped(record.content)
            let key = WordKey.identity(content.word)
            guard !key.isEmpty else {
                result.invalid += 1
                continue
            }
            let category = record.category?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let tags = (record.tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let chat = record.chat ?? []

            if keysThisBatch.contains(key) {
                result.skipped += 1
                continue
            }
            if let existing = find(key: key) {
                keysThisBatch.insert(key)
                result.idMap[record.id] = existing.id
                var changed = false
                if existing.category == nil, let category {
                    existing.category = category
                    changed = true
                }
                if existing.tags.isEmpty, !tags.isEmpty {
                    existing.tags = tags
                    changed = true
                }
                if existing.chat.isEmpty, !chat.isEmpty {
                    existing.chat = chat
                    changed = true
                }
                if record.audio != nil, !hasPronunciation(id: existing.id), let data = clip(record) {
                    store(data, for: existing)
                    clipIDs.append(existing.id)
                    result.clipsRestored += 1
                    changed = true
                }
                if changed {
                    existing.updatedAt = Date()
                    result.updated += 1
                } else {
                    result.skipped += 1
                }
                continue
            }

            // `id` is unique: reusing the backup's id would replace a different word that already has it.
            let id = (idsThisBatch.contains(record.id) || fetchByID(record.id) != nil) ? UUID() : record.id
            let word = Word(spanish: content.word, key: key, searchKey: WordKey.search(content.word), content: content, rawJSON: (try? JSONEncoder().encode(content)) ?? Data(), createdAt: record.createdAt)
            word.id = id
            word.updatedAt = record.updatedAt
            word.category = category
            word.tags = tags
            word.chat = chat
            context.insert(word)
            keysThisBatch.insert(key)
            idsThisBatch.insert(id)
            if record.audio != nil, let data = clip(record) {
                store(data, for: word)
                clipIDs.append(id)
                result.clipsRestored += 1
            }
            result.imported += 1
            result.idMap[record.id] = id
        }
        // Never report words as restored when they are not on disk.
        guard Persistence.save(context) else {
            context.rollback()
            for id in clipIDs { audio.remove(id) }
            throw PersistenceError.saveFailed
        }
        return result
    }

    /// A file when it can be written; if the disk refuses, the clip stays in the row so it is not lost.
    private func store(_ clip: Data, for word: Word) {
        if audio.write(clip, for: word.id) { word.pronunciationAudio = nil } else { word.pronunciationAudio = clip }
    }

    private func fetchByID(_ id: UUID) -> Word? {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
