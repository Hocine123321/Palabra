import XCTest
@testable import Palabra

final class PinnedWordsTests: XCTestCase {
    func testRoundTrip() {
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]
        XCTAssertEqual(PinnedWords.decode(PinnedWords.encode(ids)), ids)
        XCTAssertEqual(PinnedWords.decode(""), [])
    }

    func testDecodeSkipsGarbage() {
        let id = UUID()
        XCTAssertEqual(PinnedWords.decode("nonsense,\(id.uuidString),,42"), [id])
    }

    func testToggledPinsAndUnpins() {
        let id = UUID()
        let pinned = PinnedWords.toggled(id, in: "")
        XCTAssertEqual(PinnedWords.decode(pinned), [id])
        XCTAssertEqual(PinnedWords.decode(PinnedWords.toggled(id, in: pinned)), [])
    }

    func testToggledKeepsOtherPins() {
        let a = UUID(), b = UUID()
        let raw = PinnedWords.toggled(b, in: PinnedWords.toggled(a, in: ""))
        XCTAssertEqual(PinnedWords.decode(raw), [a, b])
        XCTAssertEqual(PinnedWords.decode(PinnedWords.toggled(a, in: raw)), [b])
    }

    func testFloatedPutsPinnedFirstAndKeepsEachGroupsOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let result = PinnedWords.floated(ids, pinned: [ids[3], ids[1]], id: { $0 })
        XCTAssertEqual(result, [ids[1], ids[3], ids[0], ids[2], ids[4]])
    }

    func testFloatedWithNoPinsIsUnchanged() {
        let ids = (0..<3).map { _ in UUID() }
        XCTAssertEqual(PinnedWords.floated(ids, pinned: [], id: { $0 }), ids)
    }

    func testFloatedIgnoresPinsOfWordsNotShown() {
        let ids = (0..<3).map { _ in UUID() }
        XCTAssertEqual(PinnedWords.floated(ids, pinned: [UUID()], id: { $0 }), ids)
    }
}
