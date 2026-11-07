import CryptoKit
import XCTest
@testable import Palabra

/// The vector below is copied from `web/test/trust-vector.json` (the web test fails if the two differ). If these pass, the
/// phone and the page agree on the match code and on how a grant is sealed, byte for byte.
final class TrustCryptoTests: XCTestCase {
    private enum Vector {
        static let phonePrivatePkcs8 = "308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b020101042039c523f3ed0a66d4c324156fdda8c0d44ad9843c4998ec4cfcfdffb146d12338a14403420004a9029c573796c29d6c0a218e279f39469a48375e08e5ccfc4063d493b31b679545876737ad1230f20387c47db8b263cdd2c2eb4e5c0d8f192b51dcd571de924d"
        static let phonePub = "04a9029c573796c29d6c0a218e279f39469a48375e08e5ccfc4063d493b31b679545876737ad1230f20387c47db8b263cdd2c2eb4e5c0d8f192b51dcd571de924d"
        static let browserPrivatePkcs8 = "308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420d4406f1754a197711d0eb35e3371f24d032e2401256422c52e6fffbbc4d8503ba144034200046c9d0fb376ce0a4a53f61ce8a199279d6ee827e2026dd0781414b0abc6b3cdc5c99baff397693caa5f82dc265e0f5302ddb5341a35c3fd3cc1743f698839dc90"
        static let browserPub = "046c9d0fb376ce0a4a53f61ce8a199279d6ee827e2026dd0781414b0abc6b3cdc5c99baff397693caa5f82dc265e0f5302ddb5341a35c3fd3cc1743f698839dc90"
        static let matchCode = "6601"
        static let secretHex = "0909090909090909090909090909090909090909090909090909090909090909"
        static let tokenHex = "0707070707070707070707070707070707070707070707070707070707070707"
        static let relayURL = "wss://palabra-relay.example.workers.dev"
        static let iv = "a0a1a2a3a4a5a6a7a8a9aaab"
        static let sealed = "c103c6ca017efa6a2879d2aa7daebb24a15d2a6f27fa06b21744ff862d0ca0792bf74259784454be88aa23902b4fab56c46881567986ef5d46a6584b3c770dd1e0fe7fd9052ef4e519941925821296c9a7d3fd07b3dc1b284ec787b886a22a9487cef69fca6ebf5a162885475bd86573273153270b8c73"
    }

    private func keys(_ pkcs8Hex: String) throws -> TrustCrypto.Keys {
        TrustCrypto.Keys(privateKey: try P256.KeyAgreement.PrivateKey(derRepresentation: try XCTUnwrap(Data(hexString: pkcs8Hex))))
    }

    func testTheKeysFromTheVectorGiveTheSamePublicHalvesAsTheWeb() throws {
        XCTAssertEqual(try keys(Vector.phonePrivatePkcs8).publicHex, Vector.phonePub)
        XCTAssertEqual(try keys(Vector.browserPrivatePkcs8).publicHex, Vector.browserPub)
    }

    func testMatchCodeMatchesTheWeb() throws {
        XCTAssertEqual(try TrustCrypto.matchCode(phonePub: Vector.phonePub, browserPub: Vector.browserPub), Vector.matchCode)
    }

    func testTheGrantTheWebSealedOpensHereAndTheOneSealedHereIsIdentical() throws {
        let browser = try keys(Vector.browserPrivatePkcs8)
        let opened = try TrustCrypto.openGrant(browser: browser, phonePub: Vector.phonePub,
                                               iv: try XCTUnwrap(Data(hexString: Vector.iv)), sealed: try XCTUnwrap(Data(hexString: Vector.sealed)))
        XCTAssertEqual(opened.secret.hex, Vector.secretHex)
        XCTAssertEqual(opened.token.hex, Vector.tokenHex)
        XCTAssertEqual(opened.relayURL, Vector.relayURL)

        let phone = try keys(Vector.phonePrivatePkcs8)
        let resealed = try TrustCrypto.sealGrant(phone: phone, browserPub: Vector.browserPub, secret: opened.secret, token: opened.token,
                                                 relayURL: Vector.relayURL, iv: try XCTUnwrap(Data(hexString: Vector.iv)))
        XCTAssertEqual(resealed.sealed.hex, Vector.sealed, "sealing here gives the same bytes as the web")
    }

    func testAFreshExchangeRoundTripsAndAMiddleManCannotOpenIt() throws {
        let phone = TrustCrypto.Keys(), browser = TrustCrypto.Keys(), attacker = TrustCrypto.Keys()
        let secret = LinkCrypto.randomBytes(32), token = LinkCrypto.randomBytes(32)
        let box = try TrustCrypto.sealGrant(phone: phone, browserPub: browser.publicHex, secret: secret, token: token, relayURL: "wss://r.example")
        let opened = try TrustCrypto.openGrant(browser: browser, phonePub: phone.publicHex, iv: box.iv, sealed: box.sealed)
        XCTAssertEqual(opened, TrustCrypto.Grant(secret: secret, token: token, relayURL: "wss://r.example"))
        XCTAssertNotEqual(try TrustCrypto.matchCode(phonePub: phone.publicHex, browserPub: browser.publicHex),
                          try TrustCrypto.matchCode(phonePub: attacker.publicHex, browserPub: browser.publicHex))
        XCTAssertThrowsError(try TrustCrypto.openGrant(browser: browser, phonePub: attacker.publicHex, iv: box.iv, sealed: box.sealed))
        XCTAssertThrowsError(try TrustCrypto.openGrant(browser: attacker, phonePub: phone.publicHex, iv: box.iv, sealed: box.sealed))
    }

    func testBadPublicKeysAreRefusedBeforeAnyMath() {
        let good = TrustCrypto.Keys().publicHex
        for bad in ["", "04", "zz", String(repeating: "00", count: 65), "05" + String(repeating: "11", count: 64)] {
            XCTAssertThrowsError(try TrustCrypto.matchCode(phonePub: bad, browserPub: good), bad)
        }
    }

    func testGrantLayoutAndTokenHash() throws {
        let secret = Data(repeating: 9, count: 32), token = Data(repeating: 7, count: 32)
        XCTAssertEqual(try TrustCrypto.unpackGrant(try TrustCrypto.packGrant(secret: secret, token: token, relayURL: "")).relayURL, "")
        XCTAssertThrowsError(try TrustCrypto.unpackGrant(Data(count: 10)))
        XCTAssertThrowsError(try TrustCrypto.packGrant(secret: secret, token: Data(count: 5), relayURL: ""))
        XCTAssertNotEqual(TrustCrypto.tokenHash(token), TrustCrypto.tokenHash(Data(repeating: 8, count: 32)))
        XCTAssertFalse(TrustCrypto.tokenHash(token).contains(token.hex))
    }
}
