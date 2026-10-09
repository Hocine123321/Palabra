import XCTest

/// Artifacts end to end with the stub AI: create, preview with live data, save, update, restore.
final class ArtifactsUITests: XCTestCase {
    private func launch(persist: Bool = false, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-UITestStub"]
        if reset { arguments += ["-UITestReset", "-UITestSeed", "3"] }
        if persist { arguments.append("-UITestPersist") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens the new-artifact sheet, asks for `request`, and taps Generate.
    private func generate(_ app: XCUIApplication, request: String, newButton: Bool = true) {
        if newButton {
            let new = app.buttons["newArtifactButton"]
            XCTAssertTrue(new.waitForExistence(timeout: 5))
            new.tap()
        }
        let field = app.textViews["artifactRequestField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(request)
        app.buttons["generateArtifactButton"].tap()
    }

    private func createAndSave(_ app: XCUIApplication) {
        generate(app, request: "a table of my words")
        XCTAssertTrue(app.staticTexts["Stub artifact"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["saveArtifactButton"].tap()
        XCTAssertTrue(element(app, "artifactRow").waitForExistence(timeout: 5))
    }

    func testStartingFromAnIdeaFillsTheRequestAndGenerates() {
        let app = launch()
        XCTAssertTrue(app.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))
        let new = app.buttons["newArtifactButton"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(element(app, "artifactFormatPicker").waitForExistence(timeout: 5))
        let generate = app.buttons["generateArtifactButton"]
        XCTAssertFalse(generate.isEnabled, "nothing to generate yet")
        let idea = element(app, "artifactIdea.table")
        XCTAssertTrue(idea.waitForExistence(timeout: 5))
        idea.tap()
        XCTAssertTrue(generate.isEnabled)
        generate.tap()
        XCTAssertTrue(app.staticTexts["Stub artifact"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["saveArtifactButton"].tap()
        XCTAssertTrue(element(app, "artifactRow").waitForExistence(timeout: 5))
    }

    func testCreateSaveOpenUpdateAndRestore() {
        let app = launch()
        XCTAssertTrue(app.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))

        generate(app, request: "a table of my words")
        XCTAssertTrue(app.staticTexts["Stub artifact"].firstMatch.waitForExistence(timeout: 10))
        // Live bind to library.words: seeded words appear in the preview.
        XCTAssertTrue(app.staticTexts["palabra0"].firstMatch.waitForExistence(timeout: 5))
        // AI strings are never identity: two identical list items both render.
        XCTAssertEqual(app.staticTexts.matching(identifier: "Same").count, 2)
        app.buttons["saveArtifactButton"].tap()

        let row = element(app, "artifactRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["First step"].waitForExistence(timeout: 5))

        // Update: the stub adds an "Updated" block.
        app.buttons["artifactMenu"].tap()
        app.buttons["Update"].tap()
        generate(app, request: "add a note", newButton: false)
        XCTAssertTrue(app.staticTexts["Updated"].waitForExistence(timeout: 10))
        app.buttons["saveArtifactButton"].tap()
        XCTAssertTrue(app.staticTexts["Updated"].waitForExistence(timeout: 5))

        // Restore version 1: the update is gone.
        app.buttons["artifactMenu"].tap()
        app.buttons["Versions"].tap()
        let restore = app.buttons["restoreVersion-1"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.staticTexts["First step"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Updated"].exists)
    }

    func testAppArtifactApprovalAndSave() {
        let app = launch()
        XCTAssertTrue(app.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))
        generate(app, request: "a practice app")

        // The app asks before it can do anything; nothing inside the web view is read (not reliable in CI).
        let allow = app.buttons["allowArtifactButton"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.buttons["saveArtifactButton"].tap()

        let row = element(app, "artifactRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        // The grant was stored with the artifact, so it does not ask again.
        XCTAssertFalse(app.buttons["allowArtifactButton"].exists)
    }

    func testFailurePathShowsRetry() {
        let app = launch()
        XCTAssertTrue(app.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))
        generate(app, request: "fallo")
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
    }

    func testChecklistTickSurvivesRelaunch() {
        let first = launch(persist: true)
        XCTAssertTrue(first.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))
        createAndSave(first)
        element(first, "artifactRow").tap()
        let step = first.buttons["First step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        step.tap()
        XCTAssertTrue(step.isSelected)
        first.terminate()

        let second = launch(persist: true, reset: false)
        XCTAssertTrue(second.openHubRow("spanishRow.artifacts", expectingNavigationBar: "Artifacts"))
        element(second, "artifactRow").tap()
        let again = second.buttons["First step"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertTrue(again.isSelected)
        XCTAssertFalse(second.buttons["Second step"].isSelected)
    }
}
