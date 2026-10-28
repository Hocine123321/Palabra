import XCTest

/// Study → Exam end to end with the stub app: a typing-only exam, its result, practicing the missed words.
final class ExamUITests: XCTestCase {
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testTypingExamResultAndPracticeMissedWords() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "5"]
        app.launch()

        app.tabBars.buttons["Study"].tap()
        let tile = element(app, "examTile")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()

        // Typing only, five questions.
        let vocabulary = element(app, "examSkill-vocabulary")
        XCTAssertTrue(vocabulary.waitForExistence(timeout: 5))
        vocabulary.tap()
        element(app, "examSkill-grammar").tap()
        app.buttons["5"].tap()
        let start = app.buttons["startExamButton"]
        XCTAssertTrue(start.isEnabled)
        start.tap()

        // Wrong answers on purpose: every word is missed.
        for _ in 0..<5 {
            let field = app.textFields["examTypedField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText("zzz\n")
            XCTAssertTrue(element(app, "examVerdict").waitForExistence(timeout: 5))
            let next = app.buttons["examNextButton"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }

        XCTAssertTrue(element(app, "examScoreCard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep practicing"].exists)
        XCTAssertTrue(element(app, "examMissedRow").exists)

        // Flag them for review.
        let flag = app.buttons["flagMissedButton"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5))
        flag.tap()
        XCTAssertTrue(element(app, "flaggedLabel").waitForExistence(timeout: 5))

        // Practice the missed words: a new exam starts.
        let practice = app.buttons["practiceMissedButton"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        practice.tap()
        XCTAssertTrue(app.textFields["examTypedField"].waitForExistence(timeout: 10))

        // Ending it before answering leaves nothing behind; Done goes back to Study, which shows the last result.
        app.buttons["endExamButton"].tap()
        app.buttons["End and See Results"].tap()
        let done = app.buttons["examDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["Last exam: 0%"].waitForExistence(timeout: 5))
    }

    func testTheExamCannotStartWithoutAnySkill() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "3"]
        app.launch()
        app.tabBars.buttons["Study"].tap()
        let tile = element(app, "examTile")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(element(app, "examSkill-vocabulary").waitForExistence(timeout: 5))
        for skill in ["vocabulary", "typing", "grammar"] { element(app, "examSkill-\(skill)").tap() }
        XCTAssertFalse(app.buttons["startExamButton"].isEnabled)
    }

    func testAnEmptyLibraryHasNothingToTest() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        app.tabBars.buttons["Study"].tap()
        let tile = element(app, "examTile")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.staticTexts["No words to test yet"].waitForExistence(timeout: 5))
    }
}
