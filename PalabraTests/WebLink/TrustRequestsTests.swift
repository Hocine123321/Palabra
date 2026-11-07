import XCTest
@testable import Palabra

final class TrustRequestsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let phone = TrustCrypto.Keys()
    private let deviceId = String(repeating: "ab", count: 16)

    private func make() -> TrustRequests { TrustRequests(deviceId: deviceId, phonePub: phone.publicHex) }
    private func id(_ n: Int) -> String { String(format: "%032x", n) }
    private func ask(_ r: inout TrustRequests, _ n: Int, at: Date? = nil, to: String? = nil, name: String? = "Chrome on Windows", pub: String? = nil) -> TrustRequests.Intake {
        r.receive(to: to ?? deviceId, browserId: id(n), name: name, pub: pub ?? TrustCrypto.Keys().publicHex, now: at ?? t0)
    }

    func testTheFirstRequestIsShownWithTheMatchCodeBothScreensCompute() throws {
        var r = make()
        let browser = TrustCrypto.Keys()
        guard case .shown(let request) = ask(&r, 1, pub: browser.publicHex) else { return XCTFail("not shown") }
        XCTAssertEqual(request.code, try TrustCrypto.matchCode(phonePub: phone.publicHex, browserPub: browser.publicHex))
        XCTAssertEqual(request.code.count, 4)
        XCTAssertEqual(r.current, request)
    }

    func testARequestForAnotherPhoneOrWithABadKeyOrIdNeverReachesThePerson() {
        var r = make()
        XCTAssertEqual(ask(&r, 1, to: String(repeating: "cd", count: 16)), .ignored)
        XCTAssertEqual(ask(&r, 2, pub: "04"), .ignored)
        XCTAssertEqual(r.receive(to: deviceId, browserId: "short", name: "x", pub: TrustCrypto.Keys().publicHex, now: t0), .ignored)
        XCTAssertEqual(r.receive(to: deviceId, browserId: nil, name: "x", pub: TrustCrypto.Keys().publicHex, now: t0), .ignored)
        XCTAssertNil(r.current)
    }

    func testOnlyOneQuestionIsOnScreenAndTheRestWaitInAShortQueue() {
        var r = make()
        if case .shown = ask(&r, 1) {} else { XCTFail() }
        XCTAssertEqual(ask(&r, 2), .queued)
        XCTAssertEqual(ask(&r, 3), .queued)
        XCTAssertEqual(ask(&r, 4), .queued)
        XCTAssertEqual(ask(&r, 5), .ignored, "a flood is not queued without limit")
        XCTAssertEqual(r.current?.browserId, id(1))
    }

    func testTheSameBrowserAskingAgainIsIgnoredAndAnAnsweredOneCannotComeBack() throws {
        var r = make()
        _ = ask(&r, 1)
        XCTAssertEqual(ask(&r, 1), .ignored)
        _ = try XCTUnwrap(r.answer(browserId: id(1), now: t0))
        XCTAssertEqual(ask(&r, 1), .ignored, "an answered request cannot be replayed")
    }

    func testAnsweringGivesTheNextQuestionAndAnAnswerIsAcceptedOnce() throws {
        var r = make()
        _ = ask(&r, 1); _ = ask(&r, 2)
        let done = try XCTUnwrap(r.answer(browserId: id(1), now: t0))
        XCTAssertEqual(done.answered.browserId, id(1))
        XCTAssertEqual(done.next?.browserId, id(2))
        XCTAssertNil(r.answer(browserId: id(1), now: t0), "the same question is not answered twice")
        XCTAssertNil(r.answer(browserId: id(9), now: t0), "an unknown question cannot be answered")
    }

    func testAQuestionNobodyAnsweredExpiresAfterSixtySecondsAndCannotBeGrantedLate() {
        var r = make()
        _ = ask(&r, 1)
        XCTAssertFalse(r.expire(now: t0.addingTimeInterval(59)))
        XCTAssertNotNil(r.current)
        XCTAssertTrue(r.expire(now: t0.addingTimeInterval(60)))
        XCTAssertNil(r.current)
        XCTAssertNil(r.answer(browserId: id(1), now: t0.addingTimeInterval(61)))
    }

    func testWhenTheCurrentOneExpiresTheNextWaitingOneTakesItsPlace() {
        var r = make()
        _ = ask(&r, 1, at: t0)
        _ = ask(&r, 2, at: t0.addingTimeInterval(30))
        XCTAssertTrue(r.expire(now: t0.addingTimeInterval(61)))
        XCTAssertEqual(r.current?.browserId, id(2))
    }

    func testClosingPairingCancelsEverything() {
        var r = make()
        _ = ask(&r, 1); _ = ask(&r, 2)
        r.cancelAll()
        XCTAssertNil(r.current)
        XCTAssertTrue(r.queue.isEmpty)
    }

    func testTheComputersNameIsCleanedAndCut() {
        var r = make()
        guard case .shown(let a) = ask(&r, 1, name: "  " + String(repeating: "n", count: 100) + "\n") else { return XCTFail() }
        XCTAssertEqual(a.name.count, 40)
        var r2 = make()
        guard case .shown(let b) = ask(&r2, 1, name: "   ") else { return XCTFail() }
        XCTAssertEqual(b.name, "A computer")
    }
}
