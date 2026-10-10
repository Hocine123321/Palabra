import XCTest

/// Study tab end to end with the stub AI: library words are mirrored into a deck and
/// reviewed; a deck can be generated from notes.
final class StudyUITests: XCTestCase {
    func testReviewMirroredVocabularyDeck() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "3"]
        app.launch()

        app.tabBars.buttons["Study"].tap()
        let reviewAll = app.buttons["reviewAllButton"]
        XCTAssertTrue(reviewAll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "todayCard").firstMatch.exists)
        reviewAll.tap()

        for _ in 0..<3 {
            let show = app.buttons["showAnswerButton"]
            XCTAssertTrue(show.waitForExistence(timeout: 5))
            show.tap()
            let good = app.buttons["grade-good"]
            XCTAssertTrue(good.waitForExistence(timeout: 5))
            good.tap()
        }
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sessionSummary").firstMatch.exists)
    }

    func testCreateDeckFromNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        app.tabBars.buttons["Study"].tap()
        let newDeck = app.buttons["newDeckButton"]
        XCTAssertTrue(newDeck.waitForExistence(timeout: 5))
        newDeck.tap()

        let notes = app.textViews["notesField"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("The mitochondria is the powerhouse of the cell.")
        app.buttons["generateCardsButton"].tap()

        let save = app.buttons["saveDeckButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(app.buttons["reviewDeckButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Front 1"].exists)

        app.buttons["addCardButton"].tap()
        let front = app.textFields["cardFrontField"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.tap()
        front.typeText("Manual front")
        let back = app.textFields["cardBackField"]
        back.tap()
        back.typeText("Manual back")
        app.buttons["saveCardButton"].tap()
        XCTAssertTrue(app.staticTexts["Manual front"].waitForExistence(timeout: 5))
    }
}
