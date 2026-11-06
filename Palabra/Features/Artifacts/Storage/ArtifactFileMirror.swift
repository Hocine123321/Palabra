import Foundation

/// A readable copy of every saved artifact as real files, so the Storage page can show them:
///
///     Application Support/Artifacts/<Title> (<id>)/v1.html, v2.html …      (apps)
///                                                  /v1.json …              (tables, charts, checklists)
///
/// The database stays the source of truth. This folder is a mirror that is only ever written from it: a failed write is ignored
/// (the artifact is saved either way), a file deleted in the Storage page comes back at the next sync, and nothing here is read
/// back into the app. So the folder is safe to browse, copy out and clean up.
struct ArtifactFileMirror: Sendable {
    let root: URL
    private var fileManager: FileManager { .default }

    init(root: URL = ArtifactFileMirror.defaultRoot()) {
        self.root = root
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artifacts", isDirectory: true)
    }

    // MARK: Names (pure)

    /// How many characters of the artifact's id end the folder name. Enough to keep two artifacts with one title apart.
    static let idSuffixLength = 8

    /// `Verb Trainer (1A2B3C4D)`: the title made safe for a file name, then the start of the id.
    static func folderName(title: String, id: UUID) -> String {
        let suffix = String(id.uuidString.prefix(idSuffixLength))
        return "\(safeTitle(title)) (\(suffix))"
    }

    /// A title that is one valid path component: no separators or control characters, no leading dot, trimmed, at most 60 characters.
    static func safeTitle(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\0").union(.controlCharacters).union(.newlines)
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : Character($0) }
        var text = String(cleaned).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        text = String(text.prefix(60)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Artifact" : text
    }

    static func fileName(version: Int, kind: ArtifactKind) -> String {
        "v\(version).\(kind == .app ? "html" : "json")"
    }

    /// Whether `folder` is the folder of artifact `id` (its name ends with the id suffix, whatever the title was).
    static func isFolder(_ folder: String, for id: UUID) -> Bool {
        folder.hasSuffix(" (\(String(id.uuidString.prefix(idSuffixLength))))")
    }

    // MARK: Writing

    /// Makes the artifact's folder match the database: one file per kept version, no others, and the folder named after the
    /// current title. Never throws; a problem leaves the folder as it was.
    func sync(id: UUID, title: String, kind: ArtifactKind, versions: [(number: Int, payload: Data)]) {
        guard (try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)) != nil else { return }
        let wanted = root.appendingPathComponent(Self.folderName(title: title, id: id), isDirectory: true)
        // A renamed artifact moves its folder instead of leaving a stale copy.
        for existing in folders(for: id) where existing.lastPathComponent != wanted.lastPathComponent {
            if fileManager.fileExists(atPath: wanted.path) {
                try? fileManager.removeItem(at: existing)
            } else {
                try? fileManager.moveItem(at: existing, to: wanted)
            }
        }
        guard (try? fileManager.createDirectory(at: wanted, withIntermediateDirectories: true)) != nil else { return }
        let keep = Set(versions.map { Self.fileName(version: $0.number, kind: kind) })
        for version in versions {
            let file = wanted.appendingPathComponent(Self.fileName(version: version.number, kind: kind))
            // Versions are immutable, so a file of the right size is the right file.
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size == version.payload.count { continue }
            try? version.payload.write(to: file, options: .atomic)
        }
        // Pruned versions leave the folder too.
        for file in (try? fileManager.contentsOfDirectory(at: wanted, includingPropertiesForKeys: nil)) ?? []
        where !keep.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    /// Removes the artifact's folder (wherever its title put it).
    func remove(id: UUID) {
        for folder in folders(for: id) { try? fileManager.removeItem(at: folder) }
    }

    /// Removes the mirror folders of artifacts that no longer exist. Only folders named the way this type names them are touched:
    /// anything else the person put in `Artifacts` (a backup, a note) is theirs and stays.
    func prune(keeping ids: Set<UUID>) {
        let kept = ids.map { String($0.uuidString.prefix(Self.idSuffixLength)) }
        for folder in allFolders() {
            let name = folder.lastPathComponent
            guard Self.looksLikeMirrorFolder(name) else { continue }
            if !kept.contains(where: { name.hasSuffix(" (\($0))") }) { try? fileManager.removeItem(at: folder) }
        }
    }

    /// `Anything (1A2B3C4D)`: ends with the 8 hex characters of an id in brackets, after a space.
    static func looksLikeMirrorFolder(_ name: String) -> Bool {
        guard name.count > Self.idSuffixLength + 3, name.hasSuffix(")") else { return false }
        let tail = name.dropLast().suffix(Self.idSuffixLength + 2)   // " (" + 8 characters
        guard tail.hasPrefix(" ("), tail.dropFirst(2).count == Self.idSuffixLength else { return false }
        return tail.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    // MARK: Reading the folder

    private func allFolders() -> [URL] {
        let items = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private func folders(for id: UUID) -> [URL] {
        allFolders().filter { Self.isFolder($0.lastPathComponent, for: id) }
    }
}
