import XCTest

/// End to end with the stub AI: empty library → add → preview → save →
/// four detail sections → chat reply → Settings. Covers the brief's launch
/// → add → view → chat flow (spec §13, §16) without a real network call.
final class SmokeUITests: XCTestCase {
    func testAddSaveViewChatAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        XCTAssertTrue(app.openVocabulary())

        XCTAssertTrue(app.staticTexts["Your library is empty"].waitForExistence(timeout: 5))

        let field = app.textFields["Add a Spanish word…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("hablar")
        app.buttons["addWordButton"].tap()

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.buttons["Example Paragraphs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Meaning & Usage"].exists)
        XCTAssertTrue(app.buttons["Word Forms"].exists)
        XCTAssertTrue(app.buttons["Similar Words"].exists)

        // Gemini TTS runs in the background after saving; once the (stubbed)
        // audio is back, the play button appears next to the headword.
        XCTAssertTrue(app.buttons["Play pronunciation"].waitForExistence(timeout: 5))

        app.buttons["Ask about this word"].tap()
        let chatField = app.textFields["Ask about this word…"]
        XCTAssertTrue(chatField.waitForExistence(timeout: 5))
        chatField.tap()
        chatField.typeText("another example")
        app.buttons["chatSendButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Think of")).firstMatch.waitForExistence(timeout: 5))

        app.swipeDown()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Back from a word detail lands on the library, not the hub.
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
