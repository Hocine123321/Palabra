import SwiftData
import XCTest
@testable import Palabra

@MainActor
final class ArtifactFileMirrorTests: XCTestCase {
    private var root: URL!
    private var mirror: ArtifactFileMirror!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        root = fm.temporaryDirectory.appendingPathComponent("mirror-\(UUID().uuidString)", isDirectory: true)
        mirror = ArtifactFileMirror(root: root)
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
        super.tearDown()
    }

    private func names(_ url: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: names

    func testFolderNameHasTheTitleAndTheStartOfTheID() {
        let id = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000")!
        XCTAssertEqual(ArtifactFileMirror.folderName(title: "Verb Trainer", id: id), "Verb Trainer (1A2B3C4D)")
    }

    func testTwoArtifactsWithOneTitleGetDifferentFolders() {
        XCTAssertNotEqual(ArtifactFileMirror.folderName(title: "Quiz", id: UUID()), ArtifactFileMirror.folderName(title: "Quiz", id: UUID()))
    }

    func testSafeTitleIsOneValidPathComponent() {
        XCTAssertEqual(ArtifactFileMirror.safeTitle("a/b\\c:d*e?f\"g<h>i|j"), "a b c d e f g h i j")
        XCTAssertEqual(ArtifactFileMirror.safeTitle("  ..hidden  "), "hidden")
        XCTAssertEqual(ArtifactFileMirror.safeTitle(""), "Artifact")
        XCTAssertEqual(ArtifactFileMirror.safeTitle("///"), "Artifact")
        XCTAssertEqual(ArtifactFileMirror.safeTitle("line\none\ttab"), "line one tab")
        XCTAssertLessThanOrEqual(ArtifactFileMirror.safeTitle(String(repeating: "x", count: 500)).count, 60)
        XCTAssertEqual(ArtifactFileMirror.safeTitle("Pronombres y verbos 🇪🇸"), "Pronombres y verbos 🇪🇸")
    }

    func testSafeTitleNeverProducesAnythingStoragePolicyRefuses() {
        for title in ["..", ".", "../../etc", "a/b", "", "  ", ".store", "x\0y"] {
            XCTAssertTrue(StoragePolicy.isPlainName(ArtifactFileMirror.folderName(title: title, id: UUID())), "\(title)")
        }
    }

    func testFileNameFollowsTheKind() {
        XCTAssertEqual(ArtifactFileMirror.fileName(version: 3, kind: .app), "v3.html")
        XCTAssertEqual(ArtifactFileMirror.fileName(version: 1, kind: .spec), "v1.json")
    }

    func testFolderBelongsToItsIDWhateverTheTitle() {
        let id = UUID()
        XCTAssertTrue(ArtifactFileMirror.isFolder(ArtifactFileMirror.folderName(title: "Old name", id: id), for: id))
        XCTAssertTrue(ArtifactFileMirror.isFolder(ArtifactFileMirror.folderName(title: "New name", id: id), for: id))
        XCTAssertFalse(ArtifactFileMirror.isFolder(ArtifactFileMirror.folderName(title: "x", id: UUID()), for: id))
    }

    func testOnlyOurOwnFolderNamesLookLikeMirrorFolders() {
        XCTAssertTrue(ArtifactFileMirror.looksLikeMirrorFolder("Verb Trainer (1A2B3C4D)"))
        XCTAssertTrue(ArtifactFileMirror.looksLikeMirrorFolder("Artifact (deadbeef)"))
        XCTAssertFalse(ArtifactFileMirror.looksLikeMirrorFolder("My backup"))
        XCTAssertFalse(ArtifactFileMirror.looksLikeMirrorFolder("Notes (2024)"))
        XCTAssertFalse(ArtifactFileMirror.looksLikeMirrorFolder("Thing (ZZZZZZZZ)"))
        XCTAssertFalse(ArtifactFileMirror.looksLikeMirrorFolder("(1A2B3C4D)"))
        XCTAssertFalse(ArtifactFileMirror.looksLikeMirrorFolder(""))
    }

    // MARK: writing

    func testSyncWritesOneFilePerVersion() {
        let id = UUID()
        mirror.sync(id: id, title: "Trainer", kind: .app, versions: [(2, data("<html>two</html>")), (1, data("<html>one</html>"))])
        let folder = root.appendingPathComponent(ArtifactFileMirror.folderName(title: "Trainer", id: id))
        XCTAssertEqual(names(folder), ["v1.html", "v2.html"])
        XCTAssertEqual(try? String(contentsOf: folder.appendingPathComponent("v2.html"), encoding: .utf8), "<html>two</html>")
    }

    func testSpecsAreWrittenAsJSON() {
        let id = UUID()
        mirror.sync(id: id, title: "Table", kind: .spec, versions: [(1, data(#"{"blocks":[]}"#))])
        XCTAssertEqual(names(root.appendingPathComponent(ArtifactFileMirror.folderName(title: "Table", id: id))), ["v1.json"])
    }

    func testSyncIsRepeatableAndLeavesUnchangedFilesAlone() throws {
        let id = UUID()
        let versions = [(number: 1, payload: data("<html>one</html>"))]
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        let file = root.appendingPathComponent(ArtifactFileMirror.folderName(title: "T", id: id)).appendingPathComponent("v1.html")
        let first = try XCTUnwrap(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        Thread.sleep(forTimeInterval: 1.1)
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        let second = try XCTUnwrap(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertEqual(first, second, "an unchanged version is not rewritten")
        XCTAssertEqual(names(file.deletingLastPathComponent()), ["v1.html"])
    }

    func testAFileDeletedByHandComesBack() {
        let id = UUID()
        let versions = [(number: 1, payload: data("<html>one</html>"))]
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        let folder = root.appendingPathComponent(ArtifactFileMirror.folderName(title: "T", id: id))
        try? fm.removeItem(at: folder.appendingPathComponent("v1.html"))
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        XCTAssertEqual(names(folder), ["v1.html"])
    }

    func testAnEditedFileIsPutBack() {
        let id = UUID()
        let versions = [(number: 1, payload: data("<html>original</html>"))]
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        let file = root.appendingPathComponent(ArtifactFileMirror.folderName(title: "T", id: id)).appendingPathComponent("v1.html")
        try? data("x").write(to: file)
        mirror.sync(id: id, title: "T", kind: .app, versions: versions)
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "<html>original</html>", "the database is the truth")
    }

    func testPrunedVersionsLeaveTheFolder() {
        let id = UUID()
        mirror.sync(id: id, title: "T", kind: .app, versions: [(2, data("b")), (1, data("a"))])
        mirror.sync(id: id, title: "T", kind: .app, versions: [(2, data("b"))])
        XCTAssertEqual(names(root.appendingPathComponent(ArtifactFileMirror.folderName(title: "T", id: id))), ["v2.html"])
    }

    func testARenamedArtifactMovesItsFolder() {
        let id = UUID()
        mirror.sync(id: id, title: "Old", kind: .app, versions: [(1, data("a"))])
        mirror.sync(id: id, title: "New", kind: .app, versions: [(1, data("a"))])
        XCTAssertEqual(names(root), [ArtifactFileMirror.folderName(title: "New", id: id)])
    }

    func testRemoveDeletesOnlyThatArtifact() {
        let a = UUID(), b = UUID()
        mirror.sync(id: a, title: "A", kind: .app, versions: [(1, data("a"))])
        mirror.sync(id: b, title: "B", kind: .app, versions: [(1, data("b"))])
        mirror.remove(id: a)
        XCTAssertEqual(names(root), [ArtifactFileMirror.folderName(title: "B", id: b)])
    }

    func testPruneRemovesGoneArtifactsButNeverTheUsersOwnFolders() {
        let kept = UUID(), gone = UUID()
        mirror.sync(id: kept, title: "Kept", kind: .app, versions: [(1, data("a"))])
        mirror.sync(id: gone, title: "Gone", kind: .app, versions: [(1, data("a"))])
        let mine = root.appendingPathComponent("My backup", isDirectory: true)
        try? fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try? data("keep me").write(to: root.appendingPathComponent("notes.txt"))
        mirror.prune(keeping: [kept])
        XCTAssertEqual(names(root), [ArtifactFileMirror.folderName(title: "Kept", id: kept), "My backup", "notes.txt"].sorted())
    }

    func testAMissingRootIsCreatedAndAnUnwritableOneDoesNotCrash() {
        let id = UUID()
        mirror.sync(id: id, title: "T", kind: .app, versions: [(1, data("a"))])
        XCTAssertTrue(fm.fileExists(atPath: root.path))
        // A file where the folder should be: nothing can be written, and nothing may throw or crash.
        let blocked = fm.temporaryDirectory.appendingPathComponent("blocked-\(UUID().uuidString)")
        try? data("x").write(to: blocked)
        defer { try? fm.removeItem(at: blocked) }
        ArtifactFileMirror(root: blocked).sync(id: id, title: "T", kind: .app, versions: [(1, data("a"))])
        ArtifactFileMirror(root: blocked).prune(keeping: [])
        ArtifactFileMirror(root: blocked).remove(id: id)
    }

    // MARK: with the repository

    private func repo() -> SwiftDataArtifactRepository {
        let schema = Schema([Artifact.self, ArtifactVersion.self, ArtifactStateEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataArtifactRepository(context: ModelContext(container), retaining: container, mirror: mirror)
    }

    func testCreateUpdateAndDeleteKeepTheFolderInStep() {
        let repository = repo()
        guard case .success(let artifact) = repository.create(title: "Trainer", kind: .app, payload: data("<html>1</html>"), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        let folder = root.appendingPathComponent(ArtifactFileMirror.folderName(title: "Trainer", id: artifact.id))
        XCTAssertEqual(names(folder), ["v1.html"])
        _ = repository.addVersion(artifactID: artifact.id, payload: data("<html>2</html>"), requested: [], prompt: "p", now: Date())
        XCTAssertEqual(names(folder), ["v1.html", "v2.html"])
        _ = repository.restore(artifactID: artifact.id, versionNumber: 1, now: Date())
        XCTAssertEqual(names(folder), ["v1.html", "v2.html", "v3.html"])
        repository.delete(id: artifact.id)
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
    }

    func testOnlyTheNewestTwentyVersionsStayAsFiles() {
        let repository = repo()
        guard case .success(let artifact) = repository.create(title: "T", kind: .app, payload: data("v1"), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        for n in 2...(ArtifactLimits.maxVersions + 3) {
            _ = repository.addVersion(artifactID: artifact.id, payload: data("v\(n)"), requested: [], prompt: "p", now: Date())
        }
        let files = names(root.appendingPathComponent(ArtifactFileMirror.folderName(title: "T", id: artifact.id)))
        XCTAssertEqual(files.count, ArtifactLimits.maxVersions)
        XCTAssertFalse(files.contains("v1.html"))
        XCTAssertTrue(files.contains("v\(ArtifactLimits.maxVersions + 3).html"))
    }

    func testAFailedSaveWritesNoFiles() {
        let repository = repo()
        let tooBig = Data(count: ArtifactLimits.maxPayloadBytes + 1)
        XCTAssertNotNil(repository.create(title: "Big", kind: .app, payload: tooBig, requested: [], prompt: "p", now: Date()).failure)
        XCTAssertTrue(names(root).isEmpty)
    }

    func testSyncMirrorFillsInArtifactsSavedBeforeTheFolderExisted() {
        let schema = Schema([Artifact.self, ArtifactVersion.self, ArtifactStateEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let old = SwiftDataArtifactRepository(context: context, retaining: container)   // no mirror: how they were saved before
        guard case .success(let artifact) = old.create(title: "Legacy", kind: .app, payload: data("<html>old</html>"), requested: [], prompt: "p", now: Date()) else { return XCTFail("create failed") }
        XCTAssertTrue(names(root).isEmpty)
        let stale = UUID()
        mirror.sync(id: stale, title: "Deleted", kind: .app, versions: [(1, data("x"))])

        SwiftDataArtifactRepository(context: context, retaining: container, mirror: mirror).syncMirror()

        XCTAssertEqual(names(root), [ArtifactFileMirror.folderName(title: "Legacy", id: artifact.id)])
    }

    func testARepositoryWithNoMirrorTouchesNoFolders() {
        let schema = Schema([Artifact.self, ArtifactVersion.self, ArtifactStateEntry.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let plain = SwiftDataArtifactRepository(context: ModelContext(container), retaining: container)
        _ = plain.create(title: "T", kind: .app, payload: data("a"), requested: [], prompt: "p", now: Date())
        plain.syncMirror()
        XCTAssertFalse(fm.fileExists(atPath: root.path))
    }

    // MARK: storage page

    func testTheFolderIsOrdinaryEditableStorageNotLiveData() {
        // It is a copy: the Storage page may delete or edit it, and the next sync puts it right.
        XCTAssertTrue(StoragePolicy.canModify(components: ["Artifacts"]))
        XCTAssertTrue(StoragePolicy.canModify(components: ["Artifacts", "Trainer (1A2B3C4D)", "v1.html"]))
        XCTAssertEqual(StoragePolicy.protection(forComponents: ["default.store"]), .liveData, "the database stays locked")
    }

    func testTheFolderIsInsideApplicationSupportSoTheBrowserCanReachIt() {
        let support = StorageRoot.applicationSupport.url()
        XCTAssertNotNil(StoragePolicy.components(of: ArtifactFileMirror.defaultRoot(), below: support))
        XCTAssertEqual(StoragePolicy.components(of: ArtifactFileMirror.defaultRoot(), below: support), ["Artifacts"])
    }
}
