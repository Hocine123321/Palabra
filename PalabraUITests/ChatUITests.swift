import XCTest

/// The assistant end to end with the stub AI: reads run at once, writes wait for Apply / Not now.
final class ChatUITests: XCTestCase {
    private func launch(seed: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-UITestStub", "-UITestReset"]
        if seed > 0 { arguments += ["-UITestSeed", "\(seed)"] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Hub -> Chat -> New chat -> types `message` and sends it.
    private func startChat(_ app: XCUIApplication, message: String) {
        XCTAssertTrue(app.openHubRow("spanishRow.chat", expectingNavigationBar: "Chat"))
        let new = app.buttons["newChatButton"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        send(app, message)
    }

    private func send(_ app: XCUIApplication, _ message: String) {
        let field = element(app, "chatField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(message)
        app.buttons["chatSendButton"].tap()
    }

    func testWriteWaitsForApplyThenWordsAppearInTheLibrary() {
        let app = launch()
        startChat(app, message: "add words")
        XCTAssertTrue(app.staticTexts["I'll add two words."].waitForExistence(timeout: 10))
        let apply = app.buttons["applyActionsButton"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "chatActionCard").exists)
        apply.tap()
        XCTAssertTrue(app.staticTexts["All done."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["applyActionsButton"].exists)

        // The queue drains in the background with the stub AI; the words land in the library.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.openVocabulary())
        XCTAssertTrue(app.staticTexts["alpha"].firstMatch.waitForExistence(timeout: 20))
    }

    func testNotNowChangesNothing() {
        let app = launch()
        startChat(app, message: "add words")
        let decline = app.buttons["declineActionsButton"]
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()
        XCTAssertTrue(app.staticTexts["Okay, I won't change anything."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["applyActionsButton"].exists)
    }

    func testReadsRunWithoutAskingAndShowAChip() {
        let app = launch(seed: 3)
        startChat(app, message: "list words")
        XCTAssertTrue(element(app, "chatReadChip").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You have some words in your library."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["applyActionsButton"].exists)
    }

    func testFailureShowsRetryAndTheChatIsSaved() {
        let app = launch()
        startChat(app, message: "fallo")
        XCTAssertTrue(app.buttons["chatRetryButton"].waitForExistence(timeout: 10))

        // Back to the list: the conversation is there, titled after the first message.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(app, "chatRow").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["fallo"].firstMatch.exists)
    }
}
