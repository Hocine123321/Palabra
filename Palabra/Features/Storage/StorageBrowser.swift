import Foundation

/// One row of the file list.
struct StorageItem: Identifiable, Equatable, Sendable {
    var url: URL
    var name: String
    var isFolder: Bool
    /// Bytes for a file; the total of everything inside for a folder.
    var size: Int64
    var modified: Date?
    var protection: StoragePolicy.Protection

    var id: String { url.path }
    var isProtected: Bool { protection != .none }
}

enum StorageError: Error, Equatable, Sendable {
    case protected
    case outsideStorage
    case invalidName
    case notFound
    case alreadyExists
    case failed(String)

    var message: String {
        switch self {
        case .protected: return "This is part of the live library and can't be changed here. You can still copy it out."
        case .outsideStorage: return "That location is outside the app's storage."
        case .invalidName: return "That name can't be used."
        case .notFound: return "That item no longer exists."
        case .alreadyExists: return "Something with that name already exists."
        case .failed: return "The operation failed."
        }
    }
}

/// Lists and changes files inside one storage root. Every change is checked by `StoragePolicy` first, and every path is
/// resolved (symlinks included) and must stay inside the root.
struct StorageBrowser: Sendable {
    let root: URL
    /// `FileManager.default` is used inline rather than stored: a stored `FileManager` is not `Sendable`.
    private var fileManager: FileManager { .default }

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath()
    }

    // MARK: Paths

    /// The components of `url` below the root after resolving symlinks, or nil when it is outside.
    func components(of url: URL) -> [String]? {
        StoragePolicy.components(of: url.resolvingSymlinksInPath(), below: root)
    }

    func protection(of url: URL) -> StoragePolicy.Protection {
        guard let parts = components(of: url) else { return .root }
        return StoragePolicy.protection(forComponents: parts)
    }

    // MARK: Listing

    /// The direct children of `folder`, folders first, then by name. Sizes of folders are totals (computed here, so call it
    /// off the main thread for a big folder).
    func list(_ folder: URL) throws -> [StorageItem] {
        guard components(of: folder) != nil else { throw StorageError.outsideStorage }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls: [URL]
        do { urls = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) }
        catch { throw StorageError.notFound }
        var items: [StorageItem] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory ?? false
            let size = isFolder ? totalSize(of: url) : Int64(values?.fileSize ?? 0)
            items.append(StorageItem(url: url, name: url.lastPathComponent, isFolder: isFolder, size: size,
                                     modified: values?.contentModificationDate, protection: protection(of: url)))
        }
        return items.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Total bytes of every file below `url` (a file's own size for a file).
    func totalSize(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard let walker = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let v = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    // MARK: Changes

    /// Throws unless `url` is inside the root and not protected.
    private func requireModifiable(_ url: URL) throws {
        guard let parts = components(of: url) else { throw StorageError.outsideStorage }
        guard StoragePolicy.canModify(components: parts) else { throw StorageError.protected }
    }

    private func requireFolderForCreating(_ folder: URL, name: String) throws -> URL {
        guard let parts = components(of: folder) else { throw StorageError.outsideStorage }
        guard StoragePolicy.isPlainName(name) else { throw StorageError.invalidName }
        guard StoragePolicy.canCreate(named: name, inFolder: parts) else { throw StorageError.protected }
        return folder.resolvingSymlinksInPath()
    }

    func delete(_ url: URL) throws {
        try requireModifiable(url)
        guard fileManager.fileExists(atPath: url.path) else { throw StorageError.notFound }
        do { try fileManager.removeItem(at: url) } catch { throw StorageError.failed(error.localizedDescription) }
    }

    func createFolder(named name: String, in folder: URL) throws {
        let parent = try requireFolderForCreating(folder, name: name)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: target.path) else { throw StorageError.alreadyExists }
        do { try fileManager.createDirectory(at: target, withIntermediateDirectories: false) } catch { throw StorageError.failed(error.localizedDescription) }
    }

    func rename(_ url: URL, to name: String) throws {
        try requireModifiable(url)
        let parent = try requireFolderForCreating(url.deletingLastPathComponent(), name: name)
        let target = parent.appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: target.path) else { throw StorageError.alreadyExists }
        do { try fileManager.moveItem(at: url, to: target) } catch { throw StorageError.failed(error.localizedDescription) }
    }

    /// Copies `source` (any file, protected ones included: a copy changes nothing) into `folder` under a free name. Returns the copy.
    /// A folder cannot be copied into itself.
    @discardableResult
    func copy(_ source: URL, into folder: URL) throws -> URL {
        guard fileManager.fileExists(atPath: source.path) else { throw StorageError.notFound }
        let parent = try requireFolderForCreating(folder, name: source.lastPathComponent)
        let src = source.resolvingSymlinksInPath()
        // `parent` is the source itself or inside it: copying a folder into itself would never end.
        if StoragePolicy.components(of: parent, below: src) != nil { throw StorageError.invalidName }
        let name = StoragePolicy.uniqueName(source.lastPathComponent) { fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }
        guard StoragePolicy.canCreate(named: name, inFolder: components(of: parent) ?? []) else { throw StorageError.protected }
        let target = parent.appendingPathComponent(name)
        do { try fileManager.copyItem(at: src, to: target) } catch { throw StorageError.failed(error.localizedDescription) }
        return target
    }

    /// Brings a file from outside the app (a picked document) into `folder`. Returns the new file.
    @discardableResult
    func importFile(from external: URL, into folder: URL) throws -> URL {
        let parent = try requireFolderForCreating(folder, name: external.lastPathComponent)
        let name = StoragePolicy.uniqueName(external.lastPathComponent) { fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }
        guard StoragePolicy.canCreate(named: name, inFolder: components(of: parent) ?? []) else { throw StorageError.protected }
        let target = parent.appendingPathComponent(name)
        let scoped = external.startAccessingSecurityScopedResource()
        defer { if scoped { external.stopAccessingSecurityScopedResource() } }
        do { try fileManager.copyItem(at: external, to: target) } catch { throw StorageError.failed(error.localizedDescription) }
        return target
    }
}
