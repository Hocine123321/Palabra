import XCTest
@testable import Palabra

final class DeckCountsTests: XCTestCase {
    func testTotalDueAddsDueAcrossDecksAndIgnoresNewCards() {
        let counts: [UUID: DeckCounts] = [
            UUID(): DeckCounts(total: 10, due: 3, new: 4),
            UUID(): DeckCounts(total: 5, due: 0, new: 5),
            UUID(): DeckCounts(total: 2, due: 2, new: 0),
        ]
        XCTAssertEqual(DeckCounts.totalDue(counts), 5)
        XCTAssertEqual(DeckCounts.totalDue([:]), 0)
    }
}
