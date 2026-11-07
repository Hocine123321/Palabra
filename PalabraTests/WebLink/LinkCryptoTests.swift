import XCTest
@testable import Palabra

final class LinkCryptoTests: XCTestCase {
    // The same fixed vectors as web/test/crypto.test.js; both were also checked with an independent Python implementation.
    private let nonce = Data(hex: "000102030405060708090a0b0c0d0e0f")
    private let secret = Data(hex: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100")

    func testProofMatchesTheWebVector() {
        XCTAssertEqual(LinkCrypto.pairingProof(code: "482913", nonce: nonce).hex,
                       "f196d356ea14e5e4b5b1d6d0f5a3a8defebbb4f7e7e72a84b41515abddb846de")
    }

    func testRoomIDMatchesTheWebVector() {
        XCTAssertEqual(LinkCrypto.roomID(secret: secret), "378eb2daefa0d2b44fa98abda123fab0")
    }

    func testWrappedSecretMatchesTheWebVector() throws {
        let wrapped = try LinkCrypto.wrapSecret(code: "482913", nonce: nonce, secret: secret, iv: Data(hex: "a0a1a2a3a4a5a6a7a8a9aaab"))
        XCTAssertEqual(wrapped.sealed.hex,
                       "0c72ab94a88039e2b8973938130fc537c30534d7914ee134dceb9f2ce955c823aeea7a7b37f149101df8342f3b64ed19")
    }

    func testProofChecks() {
        let proof = LinkCrypto.pairingProof(code: "482913", nonce: nonce)
        XCTAssertTrue(LinkCrypto.isValidProof(proof, code: "482913", nonce: nonce))
        XCTAssertFalse(LinkCrypto.isValidProof(proof, code: "482914", nonce: nonce))
        XCTAssertFalse(LinkCrypto.isValidProof(Data(), code: "482913", nonce: nonce))
    }

    func testSessionsTalkBothWaysAndRejectAbuse() throws {
        let app = LinkCrypto.Session(secret: secret, role: .app)
        let web = LinkCrypto.Session(secret: secret, role: .web)
        let frame = try app.seal(Data("ping".utf8))
        XCTAssertThrowsError(try app.open(frame)) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .bad) } // reflected
        XCTAssertEqual(try web.open(frame), Data("ping".utf8))
        XCTAssertThrowsError(try web.open(frame)) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .replayed) }
        var tampered = try app.seal(Data("x".utf8)); tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try web.open(tampered))
        XCTAssertThrowsError(try web.open(Data([1, 2, 3]))) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .short) }
        let reply = try web.seal(Data("ack".utf8))
        XCTAssertEqual(try app.open(reply), Data("ack".utf8))
    }

    /// The bug seen on a real phone: a page that reconnects starts its counter at 0 again, and the phone used to drop everything
    /// as "replayed", so the page sat on "away" with no data.
    func testAReconnectedEndIsANewStreamNotAReplay() throws {
        let app = LinkCrypto.Session(secret: secret, role: .app)
        let first = LinkCrypto.Session(secret: secret, role: .web)
        for index in 0..<3 { XCTAssertEqual(try app.open(try first.seal(Data("a\(index)".utf8))), Data("a\(index)".utf8)) }
        let reloaded = LinkCrypto.Session(secret: secret, role: .web)
        XCTAssertEqual(try app.open(try reloaded.seal(Data("again".utf8))), Data("again".utf8))
        // the old connection's frames cannot be played back, and a repeat inside the live stream is still refused
        let stale = try first.seal(Data("late".utf8))
        XCTAssertThrowsError(try app.open(stale)) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .replayed) }
        let live = try reloaded.seal(Data("x".utf8))
        XCTAssertNoThrow(try app.open(live))
        XCTAssertThrowsError(try app.open(live)) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .replayed) }
    }

    func testTheEpochIsAuthenticated() throws {
        let app = LinkCrypto.Session(secret: secret, role: .app)
        let web = LinkCrypto.Session(secret: secret, role: .web)
        var frame = try web.seal(Data("x".utf8))
        frame[12] ^= 0xFF
        XCTAssertThrowsError(try app.open(frame)) { XCTAssertEqual($0 as? LinkCrypto.FrameError, .bad) }
    }

    func testAStrangerCannotOpenFrames() throws {
        let app = LinkCrypto.Session(secret: secret, role: .app)
        let stranger = LinkCrypto.Session(secret: LinkCrypto.randomBytes(32), role: .web)
        XCTAssertThrowsError(try stranger.open(try app.seal(Data("hi".utf8))))
    }
}

extension Data {
    /// Test helper: a hex string known to be valid.
    init(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
