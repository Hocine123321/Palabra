import XCTest

/// The Books tab with the lessons bundled in the app (no network, no AI).
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

    /// Opens the History book and its reader on the first page.
    private func openHistoryReader(_ app: XCUIApplication) {
        app.tabBars.buttons["Books"].tap()
        let cover = element(app, "bookCover.history")
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "the History book is on the shelf")
        cover.tap()
        let start = element(app, "bookStart")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(element(app, "pageIndicator").waitForExistence(timeout: 10))
    }

    private func waitForTabBar(_ app: XCUIApplication, visible: Bool) {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: visible))
        let wait = XCTNSPredicateExpectation(predicate: predicate, object: app.tabBars.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed)
    }

    func testShelfShowsBothBooksAndGeographyIsEmpty() {
        let app = launch()
        app.tabBars.buttons["Books"].tap()
        XCTAssertTrue(element(app, "bookCover.history").waitForExistence(timeout: 10))
        let geography = element(app, "bookCover.geography")
        XCTAssertTrue(geography.exists)
        geography.tap()
        XCTAssertTrue(app.staticTexts["No lessons yet"].waitForExistence(timeout: 10), "an empty book says so")
        XCTAssertFalse(element(app, "bookStart").exists)
    }

    func testTurningPagesUpdatesTheIndicator() {
        let app = launch()
        openHistoryReader(app)
        let indicator = element(app, "pageIndicator")
        XCTAssertEqual(indicator.label, "Page 1 of 7")
        XCTAssertFalse(app.buttons["pagePrevious"].isEnabled, "no page before the first")
        app.buttons["pageNext"].tap()
        XCTAssertEqual(indicator.label, "Page 2 of 7")
        app.buttons["pagePrevious"].tap()
        XCTAssertEqual(indicator.label, "Page 1 of 7")
    }

    func testFocusModeHidesTheTabBarAndExits() {
        let app = launch()
        openHistoryReader(app)
        app.buttons["focusButton"].tap()
        waitForTabBar(app, visible: false)
        XCTAssertTrue(element(app, "pageIndicator").exists, "page navigation stays in Focus Mode")
        app.buttons["focusExit"].tap()
        waitForTabBar(app, visible: true)
    }

    func testMagnifyingGlassHidesAndRevealsADate() {
        let app = launch()
        openHistoryReader(app)
        let withDate = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1815")).firstMatch
        XCTAssertTrue(withDate.waitForExistence(timeout: 5), "the date is shown normally")

        element(app, "recallToggle").tap()
        XCTAssertTrue(element(app, "recallLevel").waitForExistence(timeout: 5))
        XCTAssertFalse(withDate.exists, "Essential hides the dates")

        app.buttons["recallRevealAll"].tap()
        XCTAssertTrue(withDate.waitForExistence(timeout: 5), "Reveal all shows them again")

        element(app, "recallToggle").tap()
        XCTAssertTrue(withDate.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "recallLevel").exists, "turning the mode off removes its controls")
    }

    func testContentsJumpsToAPage() {
        let app = launch()
        openHistoryReader(app)
        app.buttons["contentsButton"].tap()
        let page = element(app, "contentsPage.5")
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        page.tap()
        XCTAssertTrue(element(app, "pageIndicator").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "pageIndicator").label, "Page 5 of 7")
    }

    func testTheSavedPageIsOfferedAfterLeavingTheReader() {
        let app = launch()
        openHistoryReader(app)
        app.buttons["pageNext"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let start = element(app, "bookStart")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "Continue reading")
    }
}
