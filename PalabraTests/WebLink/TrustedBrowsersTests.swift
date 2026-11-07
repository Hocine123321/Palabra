import XCTest
@testable import Palabra

final class TrustedBrowsersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func token(_ n: UInt8) -> Data { Data(repeating: n, count: 32) }

    func testATrustedTokenIsRecognisedAndAnotherIsNot() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: "Chrome on Windows", token: token(1), now: now)
        XCTAssertTrue(list.isTrusted(token: token(1)))
        XCTAssertFalse(list.isTrusted(token: token(2)))
        XCTAssertFalse(list.isTrusted(token: Data()))
        XCTAssertFalse(list.isTrusted(token: Data(repeating: 1, count: 5)))
    }

    func testOnlyAHashIsKept() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: "x", token: token(1), now: now)
        XCTAssertFalse(list.encoded().contains(token(1).hex))
        XCTAssertFalse(list.entries[0].tokenHash.isEmpty)
    }

    func testTrustingTheSameBrowserAgainReplacesItAndTheOldTokenStopsWorking() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: "A", token: token(1), now: now)
        list.trust(id: "b1", name: "A", token: token(2), now: now)
        XCTAssertEqual(list.entries.count, 1)
        XCTAssertFalse(list.isTrusted(token: token(1)))
        XCTAssertTrue(list.isTrusted(token: token(2)))
    }

    func testTheListHasALimitAndDropsTheOldest() {
        var list = TrustedBrowsers()
        for i in 0..<(TrustedBrowsers.maxCount + 3) { list.trust(id: "b\(i)", name: "n", token: token(UInt8(i + 1)), now: now) }
        XCTAssertEqual(list.entries.count, TrustedBrowsers.maxCount)
        XCTAssertFalse(list.isTrusted(token: token(1)))
        XCTAssertTrue(list.isTrusted(token: token(UInt8(TrustedBrowsers.maxCount + 3))))
    }

    func testRemovingOneOrAllRevokesIt() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: "A", token: token(1), now: now)
        list.trust(id: "b2", name: "B", token: token(2), now: now)
        list.remove(id: "b1")
        XCTAssertFalse(list.isTrusted(token: token(1)))
        XCTAssertTrue(list.isTrusted(token: token(2)))
        list.removeAll()
        XCTAssertTrue(list.isEmpty)
    }

    func testItSurvivesSavingAndLoadingAndBadDataIsAnEmptyList() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: "Chrome on Windows", token: token(1), now: now)
        let back = TrustedBrowsers.decode(list.encoded())
        XCTAssertEqual(back, list)
        XCTAssertTrue(back.isTrusted(token: token(1)))
        XCTAssertTrue(TrustedBrowsers.decode("not json").isEmpty)
        XCTAssertTrue(TrustedBrowsers.decode(nil).isEmpty)
    }

    func testANameIsCut() {
        var list = TrustedBrowsers()
        list.trust(id: "b1", name: String(repeating: "n", count: 200), token: token(1), now: now)
        XCTAssertEqual(list.entries[0].name.count, 40)
    }
}
