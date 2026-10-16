import XCTest

/// Solve tab with the stub solver and photo reader (no network, no camera).
final class SolveUITests: XCTestCase {
    /// The Solve button sits under the keyboard; the keyboard's Done button clears the way.
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["keyboardDoneButton"]
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    func testSolveShowsAnswerThenSteps() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        let input = app.textViews["solveInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("x^2-4=0")
        dismissKeyboard(app)

        let solve = app.buttons["solveButton"]
        XCTAssertTrue(solve.isEnabled)
        solve.tap()

        XCTAssertTrue(app.navigationBars["Answer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["x = -2 or x = 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerCard").firstMatch.exists)

        // The hero card's own identifier ("answerCard") wins over the button's on iOS 26, so find it by its label.
        let steps = app.buttons["Show steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        steps.tap()
        XCTAssertTrue(app.staticTexts["x^2 = 4, so x = ±2"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Show steps"].exists, "steps are shown, the offer is gone")
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
        dismissKeyboard(app)
        app.buttons["solveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "solveError").firstMatch.waitForExistence(timeout: 10))
    }

    func testWithoutAnAppIDSolvingStillWorks() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestNoSolveKey"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        let input = app.textViews["solveInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["wolframKeyField"].exists, "no setup card: the solver needs no key")
        input.tap()
        input.typeText("x^2-4=0")
        dismissKeyboard(app)
        app.buttons["solveButton"].tap()
        XCTAssertTrue(app.navigationBars["Answer"].waitForExistence(timeout: 10))
    }

    func testSolveSettingsPageChangesHowPhotosAreHandled() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestNoSolveKey"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        XCTAssertTrue(app.staticTexts["Photos go to Gemini, which reads and solves them in one step."].waitForExistence(timeout: 5), "photos go to Gemini by default")
        let gear = app.buttons["solveSettingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        XCTAssertTrue(app.navigationBars["Solve Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["wolframKeyField"].waitForExistence(timeout: 5), "the optional Wolfram App ID lives here now")
        let onDevice = app.buttons["Read text on this device"].exists ? app.buttons["Read text on this device"] : app.staticTexts["Read text on this device"]
        XCTAssertTrue(onDevice.waitForExistence(timeout: 5))
        onDevice.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Photos are read on your device and never leave it."].waitForExistence(timeout: 5))
    }

    func testModelPickerOffersTestingAndTheSolvePageHasItsOwnModel() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()

        app.tabBars.buttons["Solve"].tap()
        app.buttons["solveSettingsButton"].tap()
        let modelRow = app.buttons["solveModelRow"]
        XCTAssertTrue(modelRow.waitForExistence(timeout: 5))
        modelRow.tap()
        XCTAssertTrue(app.buttons["automaticModelRow"].waitForExistence(timeout: 5), "can follow the main model")
        XCTAssertTrue(app.buttons["testAllModelsButton"].exists)
    }
}
