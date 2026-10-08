import XCTest

/// Need Review end to end with a seeded flagged word (`-UITestSeedReview` flags "palabra0").
final class ReviewUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "3", "-UITestSeedReview"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testFlaggedWordShowsOnPageAndHighlightAndCanBeCleared() {
        let app = launch()
        // The hub row reports the open count.
        let hubRow = element(app, "spanishRow.needReview")
        XCTAssertTrue(hubRow.waitForExistence(timeout: 10))
        XCTAssertEqual(hubRow.value as? String, "1")

        XCTAssertTrue(app.openHubRow("spanishRow.needReview", expectingNavigationBar: "Need Review"))
        XCTAssertTrue(element(app, "needReviewRow").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["palabra0"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Seeded note"].firstMatch.exists)

        // Opening the word shows the highlight with the note.
        element(app, "openNeedWordButton").tap()
        XCTAssertTrue(app.navigationBars["palabra0"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "reviewBanner").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Seeded note"].firstMatch.exists)

        // Clearing from the highlight removes it.
        element(app, "markLearnedBannerButton").tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element(app, "reviewBanner"))
        waitForExpectations(timeout: 5)

        // Back to the hub (word -> library -> hub): nothing is left to review.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.openHubRow("spanishRow.needReview", expectingNavigationBar: "Need Review"))
        XCTAssertTrue(app.staticTexts["Nothing to review"].waitForExistence(timeout: 5))
    }

    func testMarkLearnedFromThePage() {
        let app = launch()
        XCTAssertTrue(app.openHubRow("spanishRow.needReview", expectingNavigationBar: "Need Review"))
        let button = element(app, "markLearnedButton")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.staticTexts["Nothing to review"].waitForExistence(timeout: 5))
    }
}
