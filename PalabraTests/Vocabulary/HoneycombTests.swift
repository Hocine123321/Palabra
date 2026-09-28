import XCTest
@testable import Palabra

final class HoneycombTests: XCTestCase {
    func testAlternatingRowSizesFullSet() {
        XCTAssertEqual(Honeycomb.rows(Array(1...8), columns: 3), [[1, 2, 3], [4, 5], [6, 7, 8]])
    }

    func testPartialLastRow() {
        XCTAssertEqual(Honeycomb.rows(Array(1...5), columns: 3), [[1, 2, 3], [4, 5]])
    }

    func testEmptyInputProducesNoRows() {
        XCTAssertTrue(Honeycomb.rows([Int](), columns: 3).isEmpty)
    }
}
