import XCTest
@testable import Palabra

final class StorageBrowserTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var browser: StorageBrowser!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent("storage-tests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("root", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        browser = StorageBrowser(root: root)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: base) }

    @discardableResult
    private func write(_ relative: String, _ bytes: Int = 10) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func exists(_ relative: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(relative).path) }

    // MARK: listing

    func testListSortsFoldersFirstAndTotalsFolderSizes() throws {
        try write("b.txt", 5); try write("a.txt", 7); try write("Folder/x.bin", 100); try write("Folder/sub/y.bin", 50)
        let items = try browser.list(root)
        XCTAssertEqual(items.map(\.name), ["Folder", "a.txt", "b.txt"])
        XCTAssertEqual(items[0].size, 150)
        XCTAssertTrue(items[0].isFolder)
        XCTAssertEqual(items[1].size, 7)
    }

    func testListMarksTheLiveStoreProtected() throws {
        try write("default.store", 4096); try write("default.store-wal", 100); try write("notes.txt")
        let items = try browser.list(root)
        XCTAssertEqual(items.first { $0.name == "default.store" }?.protection, .liveData)
        XCTAssertEqual(items.first { $0.name == "default.store-wal" }?.isProtected, true)
        XCTAssertEqual(items.first { $0.name == "notes.txt" }?.isProtected, false)
    }

    func testListOutsideTheRootFails() {
        XCTAssertThrowsError(try browser.list(base)) { XCTAssertEqual($0 as? StorageError, .outsideStorage) }
        XCTAssertThrowsError(try browser.list(root.appendingPathComponent("../"))) { XCTAssertEqual($0 as? StorageError, .outsideStorage) }
    }

    // MARK: protection

    func testLiveDataCannotBeDeletedRenamedOrReplaced() throws {
        let store = try write("default.store", 64)
        try write("default.store-wal", 8)
        XCTAssertThrowsError(try browser.delete(store)) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertThrowsError(try browser.rename(store, to: "old.txt")) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertThrowsError(try browser.delete(root.appendingPathComponent("default.store-wal"))) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertTrue(exists("default.store"))
        XCTAssertTrue(exists("default.store-wal"))
        XCTAssertEqual(try Data(contentsOf: store).count, 64)
    }

    func testAFileInsideALiveFolderCannotBeDeleted() throws {
        let inner = try write(".default_SUPPORT/_EXTERNAL_DATA/blob", 3)
        XCTAssertThrowsError(try browser.delete(inner)) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertThrowsError(try browser.delete(root.appendingPathComponent(".default_SUPPORT"))) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertTrue(exists(".default_SUPPORT/_EXTERNAL_DATA/blob"))
    }

    func testTheRootCannotBeDeleted() {
        XCTAssertThrowsError(try browser.delete(root)) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertTrue(fm.fileExists(atPath: root.path))
    }

    func testNothingCanBeCreatedOrRenamedToALiveName() throws {
        let note = try write("notes.txt")
        XCTAssertThrowsError(try browser.rename(note, to: "default.store")) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertThrowsError(try browser.createFolder(named: "default.store", in: root)) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertTrue(exists("notes.txt"))
        XCTAssertFalse(exists("default.store"))
    }

    func testImportCannotLandOnALiveName() throws {
        let outside = base.appendingPathComponent("default.store")
        try Data([1, 2, 3]).write(to: outside)
        XCTAssertThrowsError(try browser.importFile(from: outside, into: root)) { XCTAssertEqual($0 as? StorageError, .protected) }
        XCTAssertFalse(exists("default.store"))
    }

    func testASymlinkCannotEscapeTheRoot() throws {
        let secret = base.appendingPathComponent("secret.txt")
        try Data([9]).write(to: secret)
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: base)
        XCTAssertThrowsError(try browser.delete(link.appendingPathComponent("secret.txt"))) { XCTAssertEqual($0 as? StorageError, .outsideStorage) }
        XCTAssertThrowsError(try browser.list(link)) { XCTAssertEqual($0 as? StorageError, .outsideStorage) }
        XCTAssertTrue(fm.fileExists(atPath: secret.path))
    }

    // MARK: changes

    func testDeleteRemovesAnOrdinaryFileAndFolder() throws {
        let f = try write("a.txt"); try write("Dir/x")
        try browser.delete(f)
        try browser.delete(root.appendingPathComponent("Dir"))
        XCTAssertFalse(exists("a.txt")); XCTAssertFalse(exists("Dir"))
        XCTAssertThrowsError(try browser.delete(f)) { XCTAssertEqual($0 as? StorageError, .notFound) }
    }

    func testCreateFolderAndRename() throws {
        try browser.createFolder(named: "New", in: root)
        XCTAssertTrue(exists("New"))
        XCTAssertThrowsError(try browser.createFolder(named: "New", in: root)) { XCTAssertEqual($0 as? StorageError, .alreadyExists) }
        XCTAssertThrowsError(try browser.createFolder(named: "a/b", in: root)) { XCTAssertEqual($0 as? StorageError, .invalidName) }
        XCTAssertThrowsError(try browser.createFolder(named: "..", in: root)) { XCTAssertEqual($0 as? StorageError, .invalidName) }
        let f = try write("a.txt")
        try browser.rename(f, to: "b.txt")
        XCTAssertTrue(exists("b.txt")); XCTAssertFalse(exists("a.txt"))
        try write("c.txt")
        XCTAssertThrowsError(try browser.rename(root.appendingPathComponent("b.txt"), to: "c.txt")) { XCTAssertEqual($0 as? StorageError, .alreadyExists) }
        XCTAssertThrowsError(try browser.rename(root.appendingPathComponent("b.txt"), to: "../escape")) { XCTAssertEqual($0 as? StorageError, .invalidName) }
    }

    func testCopyGivesAFreeNameAndKeepsTheOriginal() throws {
        let f = try write("a.txt", 12)
        let copy = try browser.copy(f, into: root)
        XCTAssertEqual(copy.lastPathComponent, "a 2.txt")
        let copy2 = try browser.copy(f, into: root)
        XCTAssertEqual(copy2.lastPathComponent, "a 3.txt")
        XCTAssertEqual(try Data(contentsOf: copy).count, 12)
        XCTAssertTrue(exists("a.txt"))
    }

    func testCopyIntoAnotherFolder() throws {
        let f = try write("a.txt", 3)
        try browser.createFolder(named: "Dest", in: root)
        let copy = try browser.copy(f, into: root.appendingPathComponent("Dest"))
        XCTAssertEqual(copy.deletingLastPathComponent().lastPathComponent, "Dest")
        XCTAssertEqual(copy.lastPathComponent, "a.txt")
    }

    func testAProtectedFileCanBeCopiedOutButTheCopyIsNotLive() throws {
        let store = try write("default.store", 40)
        try browser.createFolder(named: "Backups", in: root)
        let copy = try browser.copy(store, into: root.appendingPathComponent("Backups"))
        XCTAssertEqual(try Data(contentsOf: copy).count, 40)
        XCTAssertEqual(try Data(contentsOf: store).count, 40, "the original is untouched")
        XCTAssertThrowsError(try browser.copy(store, into: root), "a second live store next to the real one") { XCTAssertEqual($0 as? StorageError, .protected) }
    }

    func testCopyIntoLiveFolderIsRefused() throws {
        let f = try write("a.txt")
        try fm.createDirectory(at: root.appendingPathComponent(".default_SUPPORT"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try browser.copy(f, into: root.appendingPathComponent(".default_SUPPORT"))) { XCTAssertEqual($0 as? StorageError, .protected) }
    }

    func testAFolderCannotBeCopiedIntoItself() throws {
        try write("Dir/x.txt")
        XCTAssertThrowsError(try browser.copy(root.appendingPathComponent("Dir"), into: root.appendingPathComponent("Dir")))
        try browser.createFolder(named: "Inner", in: root.appendingPathComponent("Dir"))
        XCTAssertThrowsError(try browser.copy(root.appendingPathComponent("Dir"), into: root.appendingPathComponent("Dir/Inner")))
    }

    func testAFolderCopyCarriesItsContent() throws {
        try write("Dir/x.txt", 4); try write("Dir/sub/y.txt", 6)
        let copy = try browser.copy(root.appendingPathComponent("Dir"), into: root)
        XCTAssertEqual(copy.lastPathComponent, "Dir 2")
        XCTAssertEqual(browser.totalSize(of: copy), 10)
    }

    func testImportCopiesAnExternalFile() throws {
        let outside = base.appendingPathComponent("photo.jpg")
        try Data(repeating: 1, count: 20).write(to: outside)
        let imported = try browser.importFile(from: outside, into: root)
        XCTAssertEqual(imported.lastPathComponent, "photo.jpg")
        XCTAssertEqual(try Data(contentsOf: imported).count, 20)
        let again = try browser.importFile(from: outside, into: root)
        XCTAssertEqual(again.lastPathComponent, "photo 2.jpg")
        XCTAssertTrue(fm.fileExists(atPath: outside.path), "the source stays where it was")
    }

    func testCopyOfAMissingFileFails() {
        XCTAssertThrowsError(try browser.copy(root.appendingPathComponent("nope"), into: root)) { XCTAssertEqual($0 as? StorageError, .notFound) }
    }

    func testTotalSizeOfAMissingPathIsZero() { XCTAssertEqual(browser.totalSize(of: root.appendingPathComponent("nope")), 0) }
}
