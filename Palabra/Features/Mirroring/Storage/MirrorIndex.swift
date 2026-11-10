import Foundation

/// What the Worker is known to hold: per item id its kind and the content hash that was sent, plus the push generation.
/// A push records an item here only after the Worker accepted it, so a push that dies halfway resends exactly the rest.
/// File: `Application Support/Mirror/index.json`. A missing or corrupt file loads as empty (everything is then resent).
final class MirrorIndex {
    private struct Entry: Codable, Equatable {
        var kind: String
        var hash: String
    }

    private struct Stored: Codable {
        var generation: Int = 0
        var items: [String: Entry] = [:]
    }

    private let fileURL: URL
    private var stored: Stored

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
    }

    static func standard() -> MirrorIndex {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MirrorIndex(fileURL: base.appendingPathComponent("Mirror", isDirectory: true).appendingPathComponent("index.json"))
    }

    var generation: Int {
        get { stored.generation }
        set { stored.generation = newValue }
    }

    func hash(of itemID: String) -> String? { stored.items[itemID]?.hash }

    func itemIDs(ofKind kind: String) -> [String] { stored.items.filter { $0.value.kind == kind }.map(\.key) }

    /// Every item id except one kind (the manifest describes all the others), sorted.
    func itemIDs(excludingKind kind: String) -> [String] {
        stored.items.filter { $0.value.kind != kind }.map(\.key).sorted()
    }

    func counts(excludingKind kind: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for entry in stored.items.values where entry.kind != kind { result[entry.kind, default: 0] += 1 }
        return result
    }

    func record(itemID: String, kind: String, hash: String) { stored.items[itemID] = Entry(kind: kind, hash: hash) }

    func remove(itemID: String) { stored.items[itemID] = nil }

    func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(stored).write(to: fileURL, options: .atomic)
    }

    /// Forget everything (and delete the file), for "Stop Mirroring".
    func reset() {
        stored = Stored()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
