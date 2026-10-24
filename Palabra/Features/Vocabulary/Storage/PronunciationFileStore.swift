import Foundation

/// Where a word's pronunciation clip (a WAV, often 100 KB or more) lives: one file per word in Application Support,
/// not a column of the word's database row. A column made every fetch of a word (the library screen, export, the
/// capabilities) load every clip with it. The clips can be regenerated, so the folder is left out of backups.
struct PronunciationFileStore: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// `Application Support/Pronunciation` (created on first write).
    static func standard() -> PronunciationFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PronunciationFileStore(directory: base.appendingPathComponent("Pronunciation", isDirectory: true))
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).wav") }

    func exists(for id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    func data(for id: UUID) -> Data? { try? Data(contentsOf: url(for: id)) }

    /// False when the file could not be written; the caller then keeps the clip where it was.
    @discardableResult
    func write(_ data: Data, for id: UUID) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            try data.write(to: url(for: id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    func removeAll() { try? FileManager.default.removeItem(at: directory) }
}
