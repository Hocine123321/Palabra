import XCTest
@testable import Palabra

/// The lessons that ship inside the app. A broken lesson file fails here, before it can reach a device.
final class BundledBooksTests: XCTestCase {
    private var library: BookLibrary!

    override func setUp() {
        super.setUp()
        library = BookLibrary.load(from: BundleBookSource())
    }

    func testTheBundledCatalogueLoadsWithoutProblems() {
        XCTAssertEqual(library.problems, [])
    }

    func testBothBooksExist() {
        XCTAssertEqual(library.books.map(\.id), ["history", "geography"])
        XCTAssertEqual(library.book(id: "history")?.subject, .history)
        XCTAssertEqual(library.book(id: "geography")?.subject, .geography)
    }

    func testTheHistoryBookHasItsFirstLesson() throws {
        let history = try XCTUnwrap(library.book(id: "history"))
        XCTAssertFalse(history.isEmpty)
        XCTAssertTrue(history.isRightToLeft)
        XCTAssertEqual(history.pages.first?.page.id, "intro")
        XCTAssertEqual(history.pages.map(\.number), Array(1...history.pages.count))
    }

    func testEveryBundledPageHasContentAndUniqueId() {
        for book in library.books {
            XCTAssertEqual(Set(book.pages.map(\.id)).count, book.pages.count, "\(book.id): page ids repeat")
            for page in book.pages {
                XCTAssertFalse(page.page.blocks.isEmpty, "\(page.id) has no blocks")
                XCTAssertFalse(page.page.title.isEmpty, "\(page.id) has no title")
            }
        }
    }

    func testEveryTermUsedInTheBundledLessonsHasADefinition() {
        for book in library.books {
            for page in book.pages {
                for block in page.page.blocks {
                    for text in block.texts {
                        for case .term(_, let id) in InlineMarkup.parse(text) {
                            XCTAssertNotNil(page.glossary[id], "\(page.id): term \(id) has no definition")
                        }
                    }
                }
            }
        }
    }

    func testTheHistoryLessonHasRecallTargetsAtEveryLevel() throws {
        let history = try XCTUnwrap(library.book(id: "history"))
        var levels = Set<RecallLevel>()
        for page in history.pages {
            for block in page.page.blocks {
                for text in block.texts {
                    for case .recall(_, let level, _) in InlineMarkup.parse(text) { levels.insert(level) }
                }
            }
        }
        XCTAssertEqual(levels, Set(RecallLevel.allCases))
    }
}
