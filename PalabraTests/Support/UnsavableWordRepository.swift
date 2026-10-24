import Foundation
@testable import Palabra

/// A `WordRepository` whose writes "reach the disk" only while `canSave` is true: everything is forwarded to a real
/// repository, but `flush()` reports a failed save when it is off. Used to check that nothing is called saved (or
/// removed from the offline queue) when the store refused the write.
@MainActor
final class UnsavableWordRepository: WordRepository {
    private let base: WordRepository
    var canSave = false

    init(_ base: WordRepository) { self.base = base }

    func find(key: String) -> Word? { base.find(key: key) }
    func word(id: UUID) -> Word? { base.word(id: id) }
    func wordSummaries() -> [WordSummary] { base.wordSummaries() }
    func wordCount() -> Int { base.wordCount() }
    @discardableResult
    func insert(spanish: String, key: String, searchKey: String, content: WordContent, rawJSON: Data) -> Word {
        base.insert(spanish: spanish, key: key, searchKey: searchKey, content: content, rawJSON: rawJSON)
    }
    func replaceContent(id: UUID, content: WordContent, rawJSON: Data) { base.replaceContent(id: id, content: content, rawJSON: rawJSON) }
    func updateChat(id: UUID, messages: [ChatMessage]) { base.updateChat(id: id, messages: messages) }
    func updatePronunciation(id: UUID, audio: Data?) { base.updatePronunciation(id: id, audio: audio) }
    func pronunciation(id: UUID) -> Data? { base.pronunciation(id: id) }
    func hasPronunciation(id: UUID) -> Bool { base.hasPronunciation(id: id) }
    func migrateLegacyPronunciation(limit: Int) -> Int { base.migrateLegacyPronunciation(limit: limit) }
    func updatePlacement(id: UUID, category: String?, tags: [String]) { base.updatePlacement(id: id, category: category, tags: tags) }
    func updatePlacements(_ placements: [UUID: WordPlacement]) { base.updatePlacements(placements) }
    func clearAllPlacements() { base.clearAllPlacements() }
    func flush() -> Bool { canSave && base.flush() }
    func delete(id: UUID) { base.delete(id: id) }
    func deleteAll() { base.deleteAll() }
    func allWords() -> [Word] { base.allWords() }
    func exportData() throws -> Data { try base.exportData() }
    func importData(_ data: Data) throws -> ImportResult { try base.importData(data) }
}
