import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesToSpanishHub() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Spanish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Spanish"].exists)
    }

    func testVocabularyRowOpensLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        XCTAssertTrue(app.openVocabulary())
    }
}
