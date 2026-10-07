import XCTest

extension XCUIApplication {
    /// Taps a row on the Spanish hub and waits for the pushed screen's navigation bar.
    @discardableResult
    func openHubRow(_ identifier: String, expectingNavigationBar title: String, timeout: TimeInterval = 10) -> Bool {
        // Type-agnostic: a SwiftUI list link can surface as a button or a cell.
        let row = descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard row.waitForExistence(timeout: timeout) else {
            XCTFail("\(identifier) not found on the Spanish hub")
            return false
        }
        row.tap()
        return navigationBars[title].waitForExistence(timeout: timeout)
    }

    /// Taps the Vocabulary row on the Spanish hub and waits for the library.
    @discardableResult
    func openVocabulary(timeout: TimeInterval = 10) -> Bool {
        openHubRow("spanishRow.vocabulary", expectingNavigationBar: "Library", timeout: timeout)
    }
}
