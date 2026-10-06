import XCTest

/// Layout switching, search, and the duplicate-word confirmation dialog,
/// seeded with `-UITestSeed` so no AI call is needed to populate the library.
final class VocabularyLibraryUITests: XCTestCase {
    private func wordElement(_ app: XCUIApplication, _ word: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", word)).firstMatch
    }

    func testLayoutSwitchAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "3"]
        app.launch()
        XCTAssertTrue(app.openVocabulary())

        XCTAssertTrue(wordElement(app, "palabra0").waitForExistence(timeout: 5))

        app.buttons["Switch to readability layout"].tap()
        XCTAssertTrue(app.buttons["Switch to grid layout"].waitForExistence(timeout: 5))
        XCTAssertTrue(wordElement(app, "palabra0").waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("palabra1")
        XCTAssertTrue(wordElement(app, "palabra1").waitForExistence(timeout: 5))
        XCTAssertFalse(wordElement(app, "palabra0").exists)
    }

    func testDuplicateWordShowsConfirmationDialog() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset", "-UITestSeed", "1"]
        app.launch()
        XCTAssertTrue(app.openVocabulary())

        let field = app.textFields["Add a Spanish word…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("palabra0")
        app.buttons["addWordButton"].tap()

        XCTAssertTrue(app.buttons["Open Existing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Regenerate"].exists)
        app.buttons["Cancel"].tap()
    }
}
