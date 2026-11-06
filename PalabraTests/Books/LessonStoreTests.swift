import XCTest
@testable import Palabra

@MainActor
final class LessonStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lesson-store-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeStore() -> LessonStore { LessonStore(directory: directory, seed: BookFixtures.source) }

    private func history(_ store: LessonStore) throws -> Book {
        try XCTUnwrap(BookLibrary.load(from: store).book(id: "history"))
    }

    private func newLesson(id: String = "new-one", title: String = "New") -> Lesson {
        Lesson(id: id, title: title, pages: [LessonPage(id: "p1", title: "Page", blocks: [.paragraph("Hello")])])
    }

    func testSeedCopiesTheSourceLessonsOnceAndDeletedLessonsStayDeleted() throws {
        let store = makeStore()
        XCTAssertEqual(try history(store).lessonCount, 2)
        XCTAssertEqual(BookLibrary.load(from: store).problems.filter { $0.hasPrefix("history/") }, [])
        try store.delete(lessonID: "revolutions")
        let again = makeStore()
        XCTAssertEqual(try history(again).chapters.flatMap(\.lessons).map(\.id), ["empires"])
    }

    func testSaveNewLessonAppearsInTheLibraryAfterTheExistingPages() throws {
        let store = makeStore()
        let before = try history(store).pages.count
        try store.save(newLesson(), bookID: "history", chapterID: "unit-1")
        let book = try history(store)
        XCTAssertEqual(book.lessonCount, 3)
        XCTAssertEqual(book.pages.last?.id, "new-one/p1")
        XCTAssertEqual(book.pages.last?.number, before + 1)
        XCTAssertEqual(store.lesson(id: "new-one")?.title, "New")
    }

    func testSaveExistingLessonReplacesItAndKeepsTheCatalogueOrder() throws {
        let store = makeStore()
        var edited = try XCTUnwrap(store.lesson(id: "empires"))
        edited.title = "Empires, edited"
        try store.save(edited, bookID: "history", chapterID: "unit-1")
        let lessons = try history(store).chapters.flatMap(\.lessons)
        XCTAssertEqual(lessons.map(\.id), ["empires", "revolutions"])
        XCTAssertEqual(lessons.first?.title, "Empires, edited")
    }

    func testSaveToAnUnknownChapterOrBookThrows() {
        let store = makeStore()
        XCTAssertThrowsError(try store.save(newLesson(), bookID: "history", chapterID: "nope")) { XCTAssertEqual($0 as? LessonStoreError, .unknownChapter) }
        XCTAssertThrowsError(try store.save(newLesson(), bookID: "nope", chapterID: "unit-1")) { XCTAssertEqual($0 as? LessonStoreError, .unknownBook) }
    }

    func testUnsafeIDsAreRefused() {
        let store = makeStore()
        for id in ["", "a/b", "../x", "a.b"] {
            XCTAssertThrowsError(try store.save(newLesson(id: id), bookID: "history", chapterID: "unit-1"), id) { XCTAssertEqual($0 as? LessonStoreError, .invalidID) }
        }
    }

    func testDeleteRemovesTheFileAndTheCatalogueEntry() throws {
        let store = makeStore()
        try store.delete(lessonID: "empires")
        XCTAssertNil(store.lesson(id: "empires"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("lessons/empires.json").path))
        XCTAssertEqual(try history(store).lessonCount, 1)
        XCTAssertThrowsError(try store.delete(lessonID: "empires")) { XCTAssertEqual($0 as? LessonStoreError, .unknownLesson) }
    }

    func testAddChapterReturnsUniqueIDsAndRenameWorks() throws {
        let store = makeStore()
        let first = try store.addChapter(bookID: "history", title: "Unit 2")
        let second = try store.addChapter(bookID: "history", title: "Unit 3")
        XCTAssertNotEqual(first, second)
        try store.renameChapter(bookID: "history", chapterID: first, title: "Renamed")
        let chapters = try history(store).chapters
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters.first { $0.id == first }?.title, "Renamed")
    }

    func testCorruptLessonFileIsReportedAndTheOthersStillLoad() throws {
        let store = makeStore()
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("lessons/empires.json"))
        let library = BookLibrary.load(from: store)
        XCTAssertTrue(library.problems.contains { $0.contains("history/empires") })
        XCTAssertEqual(library.book(id: "history")?.lessonCount, 1)
        XCTAssertNotNil(library.book(id: "geography"))
    }

    func testWritesLeaveOnlyLessonFilesBehind() throws {
        let store = makeStore()
        try store.save(newLesson(), bookID: "history", chapterID: "unit-1")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("lessons").path).sorted()
        XCTAssertEqual(names, ["empires.json", "new-one.json", "revolutions.json", "rivers.json"])
    }

    func testShelfSaveBumpsLibraryVersionAndReloads() throws {
        let defaults = UserDefaults(suiteName: "store-\(UUID().uuidString)") ?? .standard
        let shelf = BookShelf(source: makeStore(), store: TextbookStateStore(defaults: defaults))
        XCTAssertEqual(shelf.libraryVersion, 0)
        try shelf.saveLesson(newLesson(), bookID: "history", chapterID: "unit-1")
        XCTAssertEqual(shelf.libraryVersion, 1)
        XCTAssertEqual(shelf.book(id: "history")?.lessonCount, 3)
        try shelf.deleteLesson(id: "new-one")
        XCTAssertEqual(shelf.libraryVersion, 2)
        XCTAssertEqual(shelf.book(id: "history")?.lessonCount, 2)
        XCTAssertNotNil(shelf.lesson(id: "empires"))
    }

    func testAShelfOverANonStoreSourceCannotSave() {
        let defaults = UserDefaults(suiteName: "store-\(UUID().uuidString)") ?? .standard
        let shelf = BookShelf(source: BookFixtures.source, store: TextbookStateStore(defaults: defaults))
        XCTAssertThrowsError(try shelf.saveLesson(newLesson(), bookID: "history", chapterID: "unit-1"))
    }
}
