import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesToLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestStub", "-UITestReset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
    }
}
