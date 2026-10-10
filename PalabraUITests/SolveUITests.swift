import XCTest

/// Solve tab with the stub solver and photo reader (no network, no camera).
final class SolveUITests: XCTestCase {
    func testSolveShowsAnswerThenSteps() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        let input = app.textViews["solveInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("x^2-4=0")

        let solve = app.buttons["solveButton"]
        XCTAssertTrue(solve.isEnabled)
        solve.tap()

        XCTAssertTrue(app.navigationBars["Answer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["x = -2 or x = 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerCard").firstMatch.exists)

        let steps = app.buttons["showStepsButton"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        steps.tap()
        XCTAssertTrue(app.staticTexts["x^2 = 4, so x = ±2"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["showStepsButton"].exists, "steps are shown, the offer is gone")
    }

    func testFailureShowsErrorBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        let input = app.textViews["solveInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("fallo")
        app.buttons["solveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "solveError").firstMatch.waitForExistence(timeout: 10))
    }

    func testWithoutAnAppIDTheSetupFieldShows() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestNoSolveKey"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        XCTAssertTrue(app.secureTextFields["wolframKeyField"].waitForExistence(timeout: 5))
    }
}
