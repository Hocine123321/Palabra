import XCTest

/// Add a word on the real on-disk store, terminate the process, relaunch,
/// and confirm the word survived — the persistence half of spec §16.
final class PersistenceUITests: XCTestCase {
    func testWordPersistsAcrossRelaunch() {
        let addApp = XCUIApplication()
        addApp.launchArguments = ["-UITestStub", "-UITestPersist", "-UITestReset"]
        addApp.launch()
        XCTAssertTrue(addApp.openVocabulary())

        let field = addApp.textFields["Add a Spanish word…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("persistente")
        addApp.buttons["addWordButton"].tap()

        let saveButton = addApp.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        XCTAssertTrue(addApp.buttons["Example Paragraphs"].waitForExistence(timeout: 5))
        addApp.terminate()

        let relaunchApp = XCUIApplication()
        relaunchApp.launchArguments = ["-UITestStub", "-UITestPersist"]
        relaunchApp.launch()
        XCTAssertTrue(relaunchApp.openVocabulary())

        XCTAssertTrue(
            relaunchApp.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "persistente")).firstMatch.waitForExistence(timeout: 5)
        )
    }
}
