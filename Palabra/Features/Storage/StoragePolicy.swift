import Foundation

/// The four places in the app's sandbox the Storage page can show.
enum StorageRoot: String, CaseIterable, Identifiable, Sendable {
    case applicationSupport, documents, caches, temporary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationSupport: return "Application Support"
        case .documents: return "Documents"
        case .caches: return "Caches"
        case .temporary: return "Temporary"
        }
    }

    var systemImage: String {
        switch self {
        case .applicationSupport: return "internaldrive"
        case .documents: return "doc.on.doc"
        case .caches: return "tray.full"
        case .temporary: return "clock.arrow.circlepath"
        }
    }

    func url() -> URL {
        let fileManager = FileManager.default
        switch self {
        case .applicationSupport: return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        case .documents: return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        case .caches: return fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        case .temporary: return fileManager.temporaryDirectory
        }
    }
}

/// Which files the Storage page may change. The live database must never be written, moved or deleted from here:
/// SwiftData keeps it open, and a half-copied or missing store loses the whole library.
///
/// Pure value logic (no file access), so it is unit-tested. Every mutating operation in `StorageBrowser` asks it first.
enum StoragePolicy {
    enum Protection: Equatable, Sendable {
        case none
        /// The live database or app settings: shown and exportable (a copy), never changed.
        case liveData
        /// The root folder itself.
        case root
    }

    /// Names (lower-cased) that belong to the live SwiftData / SQLite store and Core Data bookkeeping.
    private static let protectedNames: Set<String> = [
        "default.store", "default.store-wal", "default.store-shm",
        "default.sqlite", "default.sqlite-wal", "default.sqlite-shm",
        ".com.apple.mobile_container_manager.metadata.plist",
    ]

    private static let protectedSuffixes = [".store", ".store-wal", ".store-shm", ".sqlite", ".sqlite-wal", ".sqlite-shm", ".sqlite3", ".db", ".db-wal", ".db-shm"]

    /// Folders whose whole content is live (Core Data support files, the model catalogue cache that the app rewrites).
    private static let protectedFolders: Set<String> = [".default_support", "default_ckassets", "swiftdata", "coredata"]

    /// A single path component's protection (the file or folder name only).
    static func protection(forName name: String) -> Protection {
        let lower = name.lowercased()
        if protectedNames.contains(lower) { return .liveData }
        if protectedFolders.contains(lower) { return .liveData }
        if protectedSuffixes.contains(where: { lower.hasSuffix($0) }) { return .liveData }
        // SwiftData / Core Data's hidden support folder ("." + store name + "_SUPPORT").
        if lower.hasPrefix("."), lower.hasSuffix("_support") { return .liveData }
        return .none
    }

    /// The protection of an item given its path components below its root: it is protected when ANY component is.
    /// (A file inside a protected folder is protected too.)
    static func protection(forComponents components: [String]) -> Protection {
        if components.isEmpty { return .root }
        for part in components where protection(forName: part) == .liveData { return .liveData }
        return .none
    }

    static func canModify(components: [String]) -> Bool { protection(forComponents: components) == .none }

    /// Whether a new item named `name` may be created inside the folder at `folderComponents`.
    ///
    /// The destination folder must not be live data. A copy of a database that is dropped into an ordinary folder (a backup in
    /// Documents) is just a file and is allowed. The one exception is the top of a root: a live-store name must never appear
    /// beside the real store, where SwiftData could pick it up.
    static func canCreate(named name: String, inFolder folderComponents: [String]) -> Bool {
        guard isPlainName(name) else { return false }
        guard protection(forComponents: folderComponents) != .liveData else { return false }
        if folderComponents.isEmpty, protection(forName: name) == .liveData { return false }
        return true
    }

    /// A name that is one path component: not empty, not `.`/`..`, no separator, no control characters.
    static func isPlainName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == name, name != ".", name != ".." else { return false }
        if name.contains("/") || name.contains("\\") || name.contains("\0") { return false }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return false }
        return name.utf8.count <= 255
    }

    /// `name`, or `name 2`, `name 3` … the first one `exists` does not claim. Keeps the extension.
    static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 2
        while n < 10_000 {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
        return "\(base) \(UUID().uuidString.prefix(8))" + (ext.isEmpty ? "" : ".\(ext)")
    }

    /// The components of `path` below `root`, or nil when `path` is not inside it. Both are standardized first, so `..`
    /// and `.` cannot walk out. (Symlinks are resolved by the caller before this is used.)
    static func components(of path: URL, below root: URL) -> [String]? {
        let rootParts = root.standardizedFileURL.pathComponents
        let pathParts = path.standardizedFileURL.pathComponents
        guard pathParts.count >= rootParts.count, Array(pathParts.prefix(rootParts.count)) == rootParts else { return nil }
        return Array(pathParts.dropFirst(rootParts.count))
    }
}
