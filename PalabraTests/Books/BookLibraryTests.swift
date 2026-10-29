import XCTest
@testable import Palabra

@MainActor
final class BookLibraryTests: XCTestCase {
    private func library(_ source: StubBookSource = BookFixtures.source) -> BookLibrary {
        BookLibrary.load(from: source)
    }

    func testBooksChaptersAndPagesAreResolvedInOrder() throws {
        let library = library()
        XCTAssertEqual(library.problems, [])
        let history = try XCTUnwrap(library.book(id: "history"))
        XCTAssertEqual(history.subject, .history)
        XCTAssertEqual(history.lessonCount, 2)
        XCTAssertEqual(history.pages.map(\.id), ["empires/p1", "empires/p2", "revolutions/p1"])
        XCTAssertEqual(history.pages.map(\.number), [1, 2, 3])
        XCTAssertEqual(history.pages[2].lessonTitle, "Revolutions")
        XCTAssertEqual(history.pages[0].glossary["markets"]?.term, "Markets", "a page knows its lesson's glossary")
    }

    func testReadingDirectionFollowsTheBookLanguage() throws {
        let library = library()
        XCTAssertFalse(try XCTUnwrap(library.book(id: "history")).isRightToLeft)
        XCTAssertTrue(try XCTUnwrap(library.book(id: "geography")).isRightToLeft)
    }

    func testMissingLessonFileIsReportedAndTheRestStillLoads() throws {
        var source = BookFixtures.source
        source.lessons["lesson-revolutions"] = nil
        let library = library(source)
        XCTAssertTrue(library.problems.contains { $0.contains("history/revolutions") })
        XCTAssertEqual(try XCTUnwrap(library.book(id: "history")).pages.map(\.id), ["empires/p1", "empires/p2"])
        XCTAssertNotNil(library.book(id: "geography"))
    }

    func testBrokenLessonJSONIsReportedAndSkipped() throws {
        var source = BookFixtures.source
        source.lessons["lesson-empires"] = "{ not json"
        let library = library(source)
        XCTAssertTrue(library.problems.contains { $0.contains("history/empires") })
        XCTAssertEqual(try XCTUnwrap(library.book(id: "history")).lessonCount, 1)
    }

    func testBrokenCatalogueGivesAnEmptyLibraryNotACrash() {
        let library = library(StubBookSource(catalogue: "nope", lessons: [:]))
        XCTAssertEqual(library.books, [])
        XCTAssertEqual(library.problems.count, 1)
    }

    func testABookWithNoLessonsIsEmpty() throws {
        let source = StubBookSource(
            catalogue: #"{"books":[{"id":"geography","subject":"geography","title":"G","language":"ar","chapters":[]}]}"#,
            lessons: [:]
        )
        let book = try XCTUnwrap(library(source).book(id: "geography"))
        XCTAssertTrue(book.isEmpty)
        XCTAssertEqual(book.chapters, [])
    }

    func testAChapterWithoutLessonsStaysListed() throws {
        let source = StubBookSource(
            catalogue: #"{"books":[{"id":"history","subject":"history","title":"H","language":"ar","chapters":[{"id":"c","title":"C","lessons":[]}]}]}"#,
            lessons: [:]
        )
        let book = try XCTUnwrap(library(source).book(id: "history"))
        XCTAssertEqual(book.chapters.map(\.id), ["c"])
        XCTAssertTrue(book.isEmpty)
    }

    func testDuplicateLessonIdsAreReported() {
        let catalogue = #"{"books":[{"id":"h","subject":"history","title":"H","language":"en","chapters":[{"id":"c","title":"C","lessons":[{"id":"a","file":"lesson-revolutions"},{"id":"a","file":"lesson-revolutions"}]}]}]}"#
        let library = library(StubBookSource(catalogue: catalogue, lessons: ["lesson-revolutions": BookFixtures.revolutions]))
        XCTAssertTrue(library.problems.contains { $0.contains("used twice") })
    }

    func testValidationProblemsAreSurfacedButTheLessonStillLoads() throws {
        var source = BookFixtures.source
        source.lessons["lesson-revolutions"] = #"{"id":"revolutions","title":"R","pages":[{"id":"p1","title":"T","blocks":[{"type":"paragraph","text":"{{x|missing}}"}]}]}"#
        let library = library(source)
        XCTAssertTrue(library.problems.contains { $0.contains("unknown term id") })
        XCTAssertEqual(try XCTUnwrap(library.book(id: "history")).lessonCount, 2)
    }

    // MARK: resuming

    func testResumeFindsTheSavedPage() throws {
        let book = try XCTUnwrap(library().book(id: "history"))
        XCTAssertEqual(book.resumeIndex(lastPageID: "empires/p2"), 1)
        XCTAssertEqual(book.resumeIndex(lastPageID: nil), 0)
    }

    func testResumeFallsBackToTheLessonStartWhenThePageIsGone() throws {
        let book = try XCTUnwrap(library().book(id: "history"))
        XCTAssertEqual(book.resumeIndex(lastPageID: "revolutions/removed-page"), 2)
    }

    func testResumeFallsBackToTheFirstPageWhenTheLessonIsGone() throws {
        let book = try XCTUnwrap(library().book(id: "history"))
        XCTAssertEqual(book.resumeIndex(lastPageID: "deleted-lesson/p1"), 0)
        XCTAssertEqual(book.resumeIndex(lastPageID: "no-slash"), 0)
    }
}

@MainActor
final class BookShelfTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "dev.palabra.tests.books.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func shelf(_ source: StubBookSource = BookFixtures.source) -> BookShelf {
        BookShelf(source: source, store: TextbookStateStore(defaults: defaults))
    }

    func testVisitingPagesCountsProgressAndRemembersTheLastPage() throws {
        let shelf = shelf()
        let book = try XCTUnwrap(shelf.book(id: "history"))
        XCTAssertEqual(shelf.progress(for: book), BookShelf.Progress(read: 0, total: 3))
        shelf.recordVisit(bookID: "history", pageID: "empires/p1")
        shelf.recordVisit(bookID: "history", pageID: "empires/p2")
        shelf.recordVisit(bookID: "history", pageID: "empires/p1")
        XCTAssertEqual(shelf.progress(for: book), BookShelf.Progress(read: 2, total: 3))
        XCTAssertEqual(shelf.lastPageID(bookID: "history"), "empires/p1")
        XCTAssertEqual(shelf.progress(for: book).fraction, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testLessonProgress() throws {
        let shelf = shelf()
        let book = try XCTUnwrap(shelf.book(id: "history"))
        shelf.recordVisit(bookID: "history", pageID: "empires/p2")
        let empires = try XCTUnwrap(book.chapters.first?.lessons.first)
        XCTAssertEqual(shelf.progress(for: empires, in: book), BookShelf.Progress(read: 1, total: 2))
    }

    func testProgressSurvivesAnotherLaunch() throws {
        shelf().recordVisit(bookID: "history", pageID: "empires/p2")
        let reopened = shelf()
        XCTAssertEqual(reopened.lastPageID(bookID: "history"), "empires/p2")
        let book = try XCTUnwrap(reopened.book(id: "history"))
        XCTAssertEqual(reopened.progress(for: book).read, 1)
    }

    func testBooksKeepSeparateProgress() throws {
        let shelf = shelf()
        shelf.recordVisit(bookID: "history", pageID: "empires/p1")
        XCTAssertNil(shelf.lastPageID(bookID: "geography"))
    }

    func testAddingALessonKeepsExistingProgress() throws {
        var older = BookFixtures.source
        older.lessons["lesson-revolutions"] = nil
        shelf(older).recordVisit(bookID: "history", pageID: "empires/p2")

        let updated = shelf()   // the lesson now exists
        let book = try XCTUnwrap(updated.book(id: "history"))
        XCTAssertEqual(updated.progress(for: book), BookShelf.Progress(read: 1, total: 3))
        XCTAssertEqual(book.resumeIndex(lastPageID: updated.lastPageID(bookID: "history")), 1)
    }

    func testARewrittenLessonThatDroppedAPageResumesAtTheLessonStart() throws {
        shelf().recordVisit(bookID: "history", pageID: "empires/p2")
        var rewritten = BookFixtures.source
        rewritten.lessons["lesson-empires"] = #"{"id":"empires","version":2,"title":"Empires","pages":[{"id":"p1","title":"Rise","blocks":[{"type":"paragraph","text":"x"}]}]}"#
        let updated = shelf(rewritten)
        let book = try XCTUnwrap(updated.book(id: "history"))
        XCTAssertEqual(updated.progress(for: book).read, 0, "a page that no longer exists is not counted")
        XCTAssertEqual(book.resumeIndex(lastPageID: updated.lastPageID(bookID: "history")), 0)
    }

    func testPreferencesPersist() {
        let first = shelf()
        first.preferences.recallLevel = .intensive
        first.preferences.textSize = .larger
        let second = shelf()
        XCTAssertEqual(second.preferences.recallLevel, .intensive)
        XCTAssertEqual(second.preferences.textSize, .larger)
    }

    func testResetProgress() {
        let shelf = shelf()
        shelf.recordVisit(bookID: "history", pageID: "empires/p1")
        shelf.resetProgress(bookID: "history")
        XCTAssertNil(shelf.lastPageID(bookID: "history"))
    }
}
