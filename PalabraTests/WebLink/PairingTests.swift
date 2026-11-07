import XCTest
@testable import Palabra

final class PairingLockoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFiveWrongLockForThirtySeconds() {
        var l = PairingLockout()
        for _ in 0..<4 { XCTAssertNil(l.recordWrong(now: t0)) }
        XCTAssertEqual(l.recordWrong(now: t0), 30)
        XCTAssertTrue(l.isLocked(now: t0.addingTimeInterval(29)))
        XCTAssertFalse(l.isLocked(now: t0.addingTimeInterval(30)))
    }

    func testLockoutsGrowAndCapAtOneHour() {
        var l = PairingLockout()
        var lengths: [TimeInterval] = []
        for _ in 0..<6 {
            for _ in 0..<4 { l.recordWrong(now: t0) }
            lengths.append(l.recordWrong(now: t0)!)
        }
        XCTAssertEqual(lengths, [30, 120, 600, 3600, 3600, 3600])
    }

    func testSuccessResetsEverything() {
        var l = PairingLockout()
        for _ in 0..<5 { l.recordWrong(now: t0) }
        l.recordSuccess()
        XCTAssertEqual(l, PairingLockout())
    }

    func testSurvivesEncoding() throws {
        var l = PairingLockout()
        for _ in 0..<5 { l.recordWrong(now: t0) }
        XCTAssertEqual(try JSONDecoder().decode(PairingLockout.self, from: JSONEncoder().encode(l)), l)
    }
}

final class PairingServiceTests: XCTestCase {
    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000_000) }
    private let clock = Clock()

    private func make(persist: @escaping @Sendable (PairingLockout) -> Void = { _ in }) -> PairingService {
        let clock = self.clock
        return PairingService(now: { clock.now }, persist: persist)
    }

    private func nonce(_ service: PairingService) -> Data {
        guard case .hello(let nonce) = service.hello() else { XCTFail("no nonce"); return Data() }
        return nonce
    }

    func testCodeRules() {
        XCTAssertFalse(PairingService.isAcceptableCode("12345"))
        XCTAssertFalse(PairingService.isAcceptableCode("12345a"))
        XCTAssertFalse(PairingService.isAcceptableCode("١٢٣٤٥٦")) // non-ASCII digits
        XCTAssertTrue(PairingService.isAcceptableCode("123456"))
        XCTAssertTrue(PairingService.isAcceptableCode("12345678901"))
        XCTAssertFalse(make().open(code: "1234"))
    }

    func testNothingWorksUntilPairingIsOpened() {
        let service = make()
        XCTAssertEqual(service.hello(), .badRequest)
        XCTAssertEqual(service.pair(nonce: Data(count: 16), proof: Data()), .badRequest)
    }

    func testRightCodeReturnsASecretOnlyTheCodeOpens() throws {
        let service = make()
        let receivedBox = Box<Data?>(nil)
        service.onPaired = { receivedBox.value = $0; return true }
        service.open(code: "482913")
        let n = nonce(service)
        guard case .paired(let iv, let sealed) = service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)) else {
            return XCTFail("not paired")
        }
        let received = try XCTUnwrap(receivedBox.value)
        XCTAssertFalse(sealed.hex.contains(received.hex))               // never in the clear
        XCTAssertFalse(service.isOpen)                                    // one pairing per opening
        XCTAssertEqual(iv.count, 12)
    }

    func testWrongCodeIsRefusedAndCounted() {
        let service = make()
        service.open(code: "482913")
        let n = nonce(service)
        XCTAssertEqual(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "000000", nonce: n)), .wrong(triesLeft: 4))
        XCTAssertTrue(service.isOpen)
    }

    func testIfTheSecretCannotBeStoredThePageIsNotToldItPaired() {
        let service = make()
        service.onPaired = { _ in false }
        service.open(code: "482913")
        let n = nonce(service)
        XCTAssertEqual(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), .badRequest)
    }

    func testFifthWrongLocksAndEvenTheRightCodeIsRefusedWhileLocked() {
        let service = make()
        service.open(code: "482913")
        var last: PairingService.Reply = .badRequest
        for _ in 0..<5 {
            let n = nonce(service)
            last = service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "000000", nonce: n))
        }
        XCTAssertEqual(last, .locked(seconds: 30))
        XCTAssertEqual(service.hello(), .locked(seconds: 30))       // the page learns about it before typing a code
        let n = LinkCrypto.randomBytes(16)                           // hello refuses while locked, so pair is tried directly
        XCTAssertEqual(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), .locked(seconds: 30))
        clock.now.addTimeInterval(31)
        let n2 = nonce(service)
        if case .paired = service.pair(nonce: n2, proof: LinkCrypto.pairingProof(code: "482913", nonce: n2)) {} else { XCTFail("should pair after the lockout") }
    }

    func testLockoutPersistsAcrossRestartsOfTheService() {
        let savedBox = Box(PairingLockout())
        let first = make { savedBox.value = $0 }
        first.open(code: "482913")
        for _ in 0..<5 {
            let n = nonce(first)
            first.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "000000", nonce: n))
        }
        let clock = self.clock
        let second = PairingService(lockout: savedBox.value, now: { clock.now })
        second.open(code: "482913")                                       // a fresh code does not clear a lockout
        XCTAssertEqual(second.hello(), .locked(seconds: 30))
        let n = LinkCrypto.randomBytes(16)
        XCTAssertEqual(second.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), .locked(seconds: 30))
    }

    func testANonceWorksOnceAndExpires() {
        let service = make()
        service.open(code: "482913")
        let n = nonce(service)
        let proof = LinkCrypto.pairingProof(code: "000000", nonce: n)
        _ = service.pair(nonce: n, proof: proof)
        XCTAssertEqual(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), .badRequest) // reuse
        let stale = nonce(service)
        clock.now.addTimeInterval(121)
        XCTAssertEqual(service.pair(nonce: stale, proof: LinkCrypto.pairingProof(code: "482913", nonce: stale)), .badRequest)
    }

    func testOpeningAgainChangesTheSecret() {
        let service = make()
        let secretsBox = Box<[Data]>([])
        service.onPaired = { secretsBox.value.append($0); return true }
        for _ in 0..<2 {
            service.open(code: "482913")
            let n = nonce(service)
            _ = service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n))
        }
        let secrets = secretsBox.value
        XCTAssertEqual(secrets.count, 2)
        XCTAssertNotEqual(secrets[0], secrets[1])
    }

    /// The browser opens the sealed box with the code; what it finds is the secret, then the phone's own relay address.
    private func open(_ reply: PairingService.Reply, code: String, nonce: Data) throws -> Data {
        guard case .paired(let iv, let sealed) = reply else { XCTFail("not paired"); return Data() }
        return try LinkCrypto.unwrapSecret(code: code, nonce: nonce, iv: iv, sealed: sealed)
    }

    func testThePhoneTellsTheBrowserWhichRelayItIsOnAndTheStoredSecretStaysThirtyTwoBytes() throws {
        let stored = Box<[Data]>([])
        let service = make()
        service.relayURL = { "  wss://my-relay.example.workers.dev " }
        service.onPaired = { stored.value.append($0); return true }
        service.open(code: "482913")
        let n = nonce(service)
        let opened = try open(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), code: "482913", nonce: n)
        XCTAssertEqual(opened.count, LinkCrypto.secretBytes + "wss://my-relay.example.workers.dev".utf8.count)
        XCTAssertEqual(String(decoding: opened.suffix(from: LinkCrypto.secretBytes), as: UTF8.self), "wss://my-relay.example.workers.dev")
        XCTAssertEqual(stored.value.first, opened.prefix(LinkCrypto.secretBytes), "the phone keeps only the secret")
        XCTAssertEqual(stored.value.first?.count, LinkCrypto.secretBytes)
    }

    func testWithNoRelayAddressTheBoxIsJustTheSecretLikeBefore() throws {
        let service = make()
        service.open(code: "482913")
        let n = nonce(service)
        let opened = try open(service.pair(nonce: n, proof: LinkCrypto.pairingProof(code: "482913", nonce: n)), code: "482913", nonce: n)
        XCTAssertEqual(opened.count, LinkCrypto.secretBytes)
    }
}
