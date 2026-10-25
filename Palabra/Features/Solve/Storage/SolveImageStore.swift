import CryptoKit
import Foundation

/// The photo of a problem solved from a picture, one file per saved answer in Application Support (a column of
/// `SolveEntry` would be loaded with every list of recent answers).
struct SolveImageStore: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    static func standard() -> SolveImageStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return SolveImageStore(directory: base.appendingPathComponent("SolveImages", isDirectory: true))
    }

    /// A private folder, for tests and previews.
    static func temporary() -> SolveImageStore {
        SolveImageStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("solve-images-\(UUID().uuidString)", isDirectory: true))
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }

    func data(for id: UUID) -> Data? { try? Data(contentsOf: url(for: id)) }

    func exists(for id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    @discardableResult
    func write(_ data: Data, for id: UUID) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    func removeAll() { try? FileManager.default.removeItem(at: directory) }

    /// The saved-answer key of a photo: the same picture maps to the same key, so it is never solved (or paid for) twice.
    static func key(forPhoto data: Data) -> String {
        "photo:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
