import XCTest

extension XCUIApplication {
    /// Taps the Vocabulary row on the Spanish hub and waits for the library.
    @discardableResult
    func openVocabulary(timeout: TimeInterval = 10) -> Bool {
        // Type-agnostic: a SwiftUI list link can surface as a button or a cell.
        let row = descendants(matching: .any).matching(identifier: "spanishRow.vocabulary").firstMatch
        guard row.waitForExistence(timeout: timeout) else {
            XCTFail("Vocabulary row not found on the Spanish hub")
            return false
        }
        row.tap()
        return navigationBars["Library"].waitForExistence(timeout: timeout)
    }
}
