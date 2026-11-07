import XCTest
@testable import Palabra

final class TrustGateTests: XCTestCase {
    private let tokenA = Data(repeating: 1, count: TrustCrypto.tokenBytes)
    private let tokenB = Data(repeating: 2, count: TrustCrypto.tokenBytes)

    private func list(_ tokens: [(String, Data)]) -> TrustedBrowsers {
        var list = TrustedBrowsers()
        for (id, token) in tokens { list.trust(id: id, name: id, token: token, now: Date(timeIntervalSince1970: 0)) }
        return list
    }

    func testABrowserPairedWithTheCodePresentsNothingAndIsAnswered() {
        var gate = TrustGate()
        XCTAssertEqual(gate.hello(token: nil, trusted: TrustedBrowsers()), .allowed)
        XCTAssertEqual(gate.verdict(trusted: TrustedBrowsers()), .allowed)
    }

    func testATrustedBrowserIsAnswered() {
        var gate = TrustGate()
        let trusted = list([("a", tokenA)])
        XCTAssertEqual(gate.hello(token: tokenA, trusted: trusted), .allowed)
        XCTAssertEqual(gate.verdict(trusted: trusted), .allowed)
    }

    func testARemovedComputerIsRefusedWhileTheOthersKeepWorking() {
        var removed = TrustGate(), kept = TrustGate()
        var trusted = list([("a", tokenA), ("b", tokenB)])
        XCTAssertEqual(removed.hello(token: tokenA, trusted: trusted), .allowed)
        XCTAssertEqual(kept.hello(token: tokenB, trusted: trusted), .allowed)
        trusted.remove(id: "a")
        XCTAssertEqual(removed.verdict(trusted: trusted), .revoked, "cut off on its next request, without a reconnect")
        XCTAssertEqual(kept.verdict(trusted: trusted), .allowed, "the other computer is untouched")
    }

    func testAnUnknownTokenIsRefusedAtOnceAndStaysRefused() {
        var gate = TrustGate()
        XCTAssertEqual(gate.hello(token: tokenA, trusted: TrustedBrowsers()), .revoked)
        XCTAssertEqual(gate.verdict(trusted: list([("a", tokenA)])), .revoked, "refused for the rest of the connection, even if it is trusted afterwards")
    }

    func testANewConnectionStartsFresh() {
        var gate = TrustGate()
        _ = gate.hello(token: tokenA, trusted: TrustedBrowsers())
        gate.reset()
        XCTAssertEqual(gate.hello(token: nil, trusted: TrustedBrowsers()), .allowed)
    }

    func testAnEmptyOrWrongSizedTokenIsRefusedNotTreatedAsTheCodePath() {
        var gate = TrustGate()
        XCTAssertEqual(gate.hello(token: Data(), trusted: list([("a", tokenA)])), .revoked)
        XCTAssertEqual(gate.verdict(trusted: list([("a", tokenA)])), .revoked)
    }
}
