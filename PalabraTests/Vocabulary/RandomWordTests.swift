import XCTest
@testable import Palabra

final class RandomWordTests: XCTestCase {
    func testEmptyLibraryPicksNothing() {
        XCTAssertNil(RandomWord.pick(from: [], excluding: nil))
    }

    func testSingleWordIsPickedEvenIfItWasJustShown() {
        let only = UUID()
        XCTAssertEqual(RandomWord.pick(from: [only], excluding: only), only)
    }

    func testNeverRepeatsTheLastWordWhenThereIsAChoice() {
        let ids = (0..<5).map { _ in UUID() }
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let picked = RandomWord.pick(from: ids, excluding: ids[2], using: &generator)
            XCTAssertNotNil(picked)
            XCTAssertNotEqual(picked, ids[2])
        }
    }

    func testEveryOtherWordCanBePicked() {
        let ids = (0..<4).map { _ in UUID() }
        var generator = SeededGenerator(seed: 11)
        let seen = Set((0..<200).compactMap { _ in RandomWord.pick(from: ids, excluding: ids[0], using: &generator) })
        XCTAssertEqual(seen, Set(ids.dropFirst()))
    }
}
