import Foundation

/// Words the person pinned to the top of the library. Stored as a comma-separated list of ids under one
/// UserDefaults key (`@AppStorage`), so no SwiftData change. Pins are not part of a library backup.
enum PinnedWords {
    static let key = "pinnedWordIDs"

    static func decode(_ raw: String) -> Set<UUID> {
        Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    /// The stored text after pinning (or unpinning) one word.
    static func toggled(_ id: UUID, in raw: String) -> String {
        var ids = decode(raw)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        return encode(ids)
    }

    /// Pinned items first, each group keeping its order.
    static func floated<T>(_ items: [T], pinned: Set<UUID>, id: (T) -> UUID) -> [T] {
        guard !pinned.isEmpty else { return items }
        return items.filter { pinned.contains(id($0)) } + items.filter { !pinned.contains(id($0)) }
    }
}
