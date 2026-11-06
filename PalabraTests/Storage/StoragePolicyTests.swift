import XCTest
@testable import Palabra

final class StoragePolicyTests: XCTestCase {
    func testLiveStoreFilesAreProtected() {
        for name in ["default.store", "default.store-wal", "default.store-shm", "Default.Store", "default.sqlite", "library.sqlite3", "x.db", "x.db-wal"] {
            XCTAssertEqual(StoragePolicy.protection(forName: name), .liveData, name)
        }
    }

    func testSupportFoldersAreProtected() {
        for name in [".default_SUPPORT", ".default_support", "default_ckAssets", "SwiftData", ".anything_SUPPORT"] {
            XCTAssertEqual(StoragePolicy.protection(forName: name), .liveData, name)
        }
    }

    func testOrdinaryFilesAreNotProtected() {
        for name in ["notes.txt", "SolveImages", "Pronunciation", "ModelCatalogue.json", "photo.jpg", "store.txt", "mystore"] {
            XCTAssertEqual(StoragePolicy.protection(forName: name), .none, name)
        }
    }

    func testAFileInsideAProtectedFolderIsProtected() {
        XCTAssertEqual(StoragePolicy.protection(forComponents: [".default_SUPPORT", "_EXTERNAL_DATA", "abc"]), .liveData)
        XCTAssertEqual(StoragePolicy.protection(forComponents: ["Pronunciation", "x.wav"]), .none)
        XCTAssertEqual(StoragePolicy.protection(forComponents: []), .root)
    }

    func testCanModify() {
        XCTAssertTrue(StoragePolicy.canModify(components: ["SolveImages", "a.jpg"]))
        XCTAssertFalse(StoragePolicy.canModify(components: ["default.store"]))
        XCTAssertFalse(StoragePolicy.canModify(components: []), "the root itself cannot be deleted or renamed")
    }

    func testCreatingNextToTheLiveStoreIsRefused() {
        XCTAssertFalse(StoragePolicy.canCreate(named: "default.store", inFolder: []))
        XCTAssertFalse(StoragePolicy.canCreate(named: "x.sqlite", inFolder: []))
        XCTAssertTrue(StoragePolicy.canCreate(named: "notes.txt", inFolder: []))
    }

    func testABackupCopyOfADatabaseIsAllowedInAnOrdinaryFolder() {
        XCTAssertTrue(StoragePolicy.canCreate(named: "default.store", inFolder: ["Backups"]))
        XCTAssertFalse(StoragePolicy.canCreate(named: "a.txt", inFolder: [".default_SUPPORT"]), "nothing is added to live folders")
    }

    func testNames() {
        for bad in ["", " ", ".", "..", "a/b", "a\\b", "a\0b", " lead", "trail ", "\n", String(repeating: "x", count: 256)] {
            XCTAssertFalse(StoragePolicy.isPlainName(bad), "\(bad.debugDescription)")
        }
        for good in ["a", "my file.txt", "ñandú.png", "..hidden", "file.tar.gz", "عربى.txt"] {
            XCTAssertTrue(StoragePolicy.isPlainName(good), good)
        }
    }

    func testUniqueName() {
        XCTAssertEqual(StoragePolicy.uniqueName("a.txt") { _ in false }, "a.txt")
        XCTAssertEqual(StoragePolicy.uniqueName("a.txt") { ["a.txt"].contains($0) }, "a 2.txt")
        XCTAssertEqual(StoragePolicy.uniqueName("a.txt") { ["a.txt", "a 2.txt"].contains($0) }, "a 3.txt")
        XCTAssertEqual(StoragePolicy.uniqueName("folder") { ["folder"].contains($0) }, "folder 2")
        XCTAssertEqual(StoragePolicy.uniqueName("x.tar.gz") { ["x.tar.gz"].contains($0) }, "x.tar 2.gz")
        XCTAssertEqual(StoragePolicy.uniqueName(".hidden") { [".hidden"].contains($0) }, ".hidden 2")
    }

    func testComponentsRejectEscapes() {
        let root = URL(fileURLWithPath: "/tmp/root")
        XCTAssertEqual(StoragePolicy.components(of: URL(fileURLWithPath: "/tmp/root/a/b.txt"), below: root), ["a", "b.txt"])
        XCTAssertEqual(StoragePolicy.components(of: root, below: root), [])
        XCTAssertNil(StoragePolicy.components(of: URL(fileURLWithPath: "/tmp/root/../other/x"), below: root))
        XCTAssertNil(StoragePolicy.components(of: URL(fileURLWithPath: "/tmp/rootx/a"), below: root), "a sibling that shares a prefix is outside")
        XCTAssertNil(StoragePolicy.components(of: URL(fileURLWithPath: "/etc/passwd"), below: root))
    }
}
