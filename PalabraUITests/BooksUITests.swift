import XCTest

/// The Books tab: a 3D desk drawn by SceneKit, with SwiftUI controls over it. The 3D books can't be queried, so the
/// tests drive the controls the app puts over the scene (they do exactly what tapping the books does).
final class BooksUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens the History book from the desk and waits for the page indicator.
    private func openHistory(_ app: XCUIApplication) {
        app.tabBars.buttons["Books"].tap()
        let cover = element(app, "bookCover.history")
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "the History book is on the desk")
        // The scene needs a moment to build its page textures before it accepts a book.
        XCTAssertTrue(element(app, "booksLoading").waitForNonExistence(timeout: 30), "the scene finished loading")
        // On a cold start the scene can still be settling when the first tap lands, so tap again if nothing opened.
        var opened = false
        for _ in 0..<3 where !opened {
            cover.tap()
            opened = element(app, "pageIndicator").waitForExistence(timeout: 12)
        }
        XCTAssertTrue(opened, "the book opened")
    }

    private func waitForTabBar(_ app: XCUIApplication, visible: Bool) {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: visible))
        let wait = XCTNSPredicateExpectation(predicate: predicate, object: app.tabBars.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed)
    }

    /// "Page 1 of N" -> N, so the tests don't depend on how many pages the lesson lays out to.
    private func pageCount(_ indicator: XCUIElement) -> Int {
        Int(indicator.label.components(separatedBy: " ").last ?? "") ?? 0
    }

    private func waitForSelected(_ element: XCUIElement, _ selected: Bool, _ message: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed, message)
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed, "expected \(label), got \(element.label)")
    }

    func testTheDeskOffersBothBooksAndGeographyIsEmpty() {
        let app = launch()
        app.tabBars.buttons["Books"].tap()
        XCTAssertTrue(element(app, "bookCover.history").waitForExistence(timeout: 10))
        let geography = element(app, "bookCover.geography")
        XCTAssertTrue(geography.exists)
        XCTAssertTrue(element(app, "booksLoading").waitForNonExistence(timeout: 30))
        geography.tap()
        XCTAssertTrue(element(app, "booksNotice").waitForExistence(timeout: 10), "an empty book says so")
        XCTAssertFalse(element(app, "pageIndicator").exists)
    }

    /// One launch walks the whole reading flow (every launch costs ~30 s of CI time): pages, Focus Mode, Memorize and the
    /// tools, back to the desk, then "Read as text".
    func testReadingFlow() {
        let app = launch()
        openHistory(app)
        waitForTabBar(app, visible: false)

        // Pages.
        let indicator = element(app, "pageIndicator")
        let count = pageCount(indicator)
        XCTAssertGreaterThan(count, 1)
        waitForLabel(indicator, "Page 1 of \(count)")
        XCTAssertFalse(app.buttons["pagePrevious"].isEnabled, "no page before the first")
        app.buttons["pageNext"].tap()
        waitForLabel(indicator, "Page 2 of \(count)")
        app.buttons["pagePrevious"].tap()
        waitForLabel(indicator, "Page 1 of \(count)")

        // Focus Mode.
        app.buttons["focusButton"].tap()
        XCTAssertTrue(element(app, "focusExit").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "pageIndicator").exists, "page navigation stays in Focus Mode")
        app.buttons["focusExit"].tap()
        XCTAssertTrue(element(app, "focusButton").waitForExistence(timeout: 5))

        // Memorize and the tools.
        element(app, "recallToggle").tap()
        XCTAssertTrue(element(app, "recallLevel").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "recallReveal").exists)
        app.buttons["toolLens"].tap()
        waitForSelected(app.buttons["toolLens"], true, "the magnifying glass is in use")
        app.buttons["toolLens"].tap()
        waitForSelected(app.buttons["toolLens"], false, "tapping again puts it back on the desk")
        element(app, "recallToggle").tap()
        XCTAssertFalse(element(app, "recallLevel").exists, "turning the mode off removes its controls")

        // Back to the desk and the tab bar.
        app.buttons["bookBack"].tap()
        XCTAssertTrue(element(app, "bookCover.history").waitForExistence(timeout: 10))
        waitForTabBar(app, visible: true)

        // "Read as text" is still there.
        XCTAssertTrue(element(app, "readAsText").waitForExistence(timeout: 10))
        element(app, "readAsText").tap()
        app.buttons["التاريخ"].firstMatch.tap()
        XCTAssertTrue(element(app, "bookStart").waitForExistence(timeout: 10), "the lesson list is one tap away")
    }
}
