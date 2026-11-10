import XCTest
@testable import Palabra

final class MirrorIndexTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-index-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var file: URL { directory.appendingPathComponent("index.json") }

    func testRecordsAndRemovalsPersist() throws {
        let index = MirrorIndex(fileURL: file)
        index.record(itemID: "a", kind: "word", hash: "h1")
        index.record(itemID: "b", kind: "deck", hash: "h2")
        index.record(itemID: "c", kind: "word", hash: "h3")
        index.remove(itemID: "c")
        index.generation = 4
        try index.save()
        let again = MirrorIndex(fileURL: file)
        XCTAssertEqual(again.hash(of: "a"), "h1")
        XCTAssertNil(again.hash(of: "c"))
        XCTAssertEqual(again.itemIDs(ofKind: "word"), ["a"])
        XCTAssertEqual(again.itemIDs(ofKind: "deck"), ["b"])
        XCTAssertEqual(again.generation, 4)
    }

    func testCorruptOrMissingFileLoadsEmpty() throws {
        XCTAssertEqual(MirrorIndex(fileURL: file).generation, 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: file)
        let index = MirrorIndex(fileURL: file)
        XCTAssertEqual(index.generation, 0)
        XCTAssertTrue(index.itemIDs(ofKind: "word").isEmpty)
    }

    func testResetDeletesTheFile() throws {
        let index = MirrorIndex(fileURL: file)
        index.record(itemID: "a", kind: "word", hash: "h")
        try index.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        index.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(index.hash(of: "a"))
        XCTAssertEqual(index.generation, 0)
    }

    func testIDsAndCountsExcludeAKind() {
        let index = MirrorIndex(fileURL: file)
        index.record(itemID: "w2", kind: "word", hash: "a")
        index.record(itemID: "w1", kind: "word", hash: "b")
        index.record(itemID: "w3", kind: "word", hash: "c")
        index.record(itemID: "m", kind: "manifest", hash: "d")
        XCTAssertEqual(index.itemIDs(excludingKind: "manifest"), ["w1", "w2", "w3"])
        XCTAssertEqual(index.counts(excludingKind: "manifest"), ["word": 3])
        XCTAssertEqual(MirrorIndex(fileURL: directory.appendingPathComponent("none.json")).counts(excludingKind: "manifest"), [:])
    }
}
