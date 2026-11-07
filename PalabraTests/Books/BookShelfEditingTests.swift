import XCTest
@testable import Palabra

@MainActor
final class BookShelfEditingTests: XCTestCase {
    private func firstLessonID(_ shelf: BookShelf) throws -> (book: String, lesson: String) {
        for book in shelf.library.books {
            if let lesson = book.chapters.flatMap(\.lessons).first { return (book.id, lesson.id) }
        }
        throw XCTSkip("the bundled catalogue has no lesson")
    }

    func testEditingASavedLessonPersistsReloadsTheLibraryAndBumpsTheVersion() throws {
        let shelf = BookShelf.inMemory()
        let ids = try firstLessonID(shelf)
        let before = shelf.libraryVersion
        let firstPage = try XCTUnwrap(shelf.lesson(id: ids.lesson)?.pages.first)

        let saved = shelf.editLesson(id: ids.lesson) {
            LessonEditor.setPageTitle($0, pageID: firstPage.id, title: "Edited title")
        }

        XCTAssertTrue(saved)
        XCTAssertGreaterThan(shelf.libraryVersion, before)
        XCTAssertEqual(shelf.lesson(id: ids.lesson)?.pages.first?.title, "Edited title")
        let page = shelf.book(id: ids.book)?.pages.first { $0.id == "\(ids.lesson)/\(firstPage.id)" }
        XCTAssertEqual(page?.page.title, "Edited title", "the reader's pages come from the same library")
    }

    func testAnEditThatChangesNothingSucceedsWithoutWriting() throws {
        let shelf = BookShelf.inMemory()
        let ids = try firstLessonID(shelf)
        let before = shelf.libraryVersion
        XCTAssertTrue(shelf.editLesson(id: ids.lesson) { $0 })
        XCTAssertEqual(shelf.libraryVersion, before)
    }

    func testAnUnknownLessonIsRefused() {
        XCTAssertFalse(BookShelf.inMemory().editLesson(id: "no-such-lesson") { $0 })
    }
}
