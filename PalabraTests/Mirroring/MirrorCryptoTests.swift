import CryptoKit
import XCTest
@testable import Palabra

private final class MirrorVectorsToken {}

/// The shared protocol vectors (`Fixtures/mirror-vectors.json`), also reproduced by `web/test/crypto.test.js`.
struct MirrorVectors: Decodable {
    struct ID: Decodable { let kind: String, recordId: String, expected: String }
    struct Item: Decodable { let plaintextUtf8: String, ivHex: String, expectedSealed: String }
    struct Pair: Decodable {
        let browserPrivHex: String, phonePrivHex: String, browserPubHex: String, phonePubHex: String
        let nonceHex: String, pairId: String, kPairHex: String, matchCode: String
    }
    struct Wrap: Decodable { let plaintextUtf8: String, ivHex: String, expectedSealed: String }
    let dataKeyHex: String
    let id: ID
    let item: Item
    let pair: Pair
    let wrap: Wrap
    struct Manifest: Decodable { let ids: [String], idsHashHex: String }
    struct Empty: Decodable { let idsHashHex: String }
    struct Rotation: Decodable {
        let deviceKeyHex: String, mirrorId: String, deviceId: String, epoch: Int
        let ivHex: String, newDataKeyHex: String, plaintextUtf8: String, expectedSealed: String
    }
    let manifest: Manifest
    let empty: Empty
    let rotation: Rotation

    static func load() throws -> MirrorVectors {
        let bundle = Bundle(for: MirrorVectorsToken.self)
        guard let url = bundle.url(forResource: "mirror-vectors", withExtension: "json") else {
            throw NSError(domain: "MirrorVectors", code: 1, userInfo: [NSLocalizedDescriptionKey: "mirror-vectors.json is not in the test bundle"])
        }
        return try JSONDecoder().decode(MirrorVectors.self, from: Data(contentsOf: url))
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}

final class MirrorCryptoTests: XCTestCase {
    private func keys(_ v: MirrorVectors) throws -> MirrorKeys {
        try XCTUnwrap(MirrorKeys(dataKey: Data(hex: v.dataKeyHex)))
    }

    func testItemIDMatchesVector() throws {
        let v = try MirrorVectors.load()
        XCTAssertEqual(MirrorCrypto.itemID(keys: try keys(v), kind: v.id.kind, recordID: v.id.recordId), v.id.expected)
        XCTAssertNotEqual(MirrorCrypto.itemID(keys: try keys(v), kind: "deck", recordID: v.id.recordId), v.id.expected)
    }

    func testSealReproducesVectorAndOpens() throws {
        let v = try MirrorVectors.load()
        let sealed = try MirrorCrypto.sealItem(keys: try keys(v), itemID: v.id.expected, plaintext: Data(v.item.plaintextUtf8.utf8), iv: Data(hex: v.item.ivHex))
        XCTAssertEqual(Base64URL.encode(sealed), v.item.expectedSealed)
        let opened = try MirrorCrypto.openItem(keys: try keys(v), itemID: v.id.expected, sealed: sealed)
        XCTAssertEqual(String(decoding: opened, as: UTF8.self), v.item.plaintextUtf8)
    }

    func testTamperingWrongIDAndShortInputFail() throws {
        let v = try MirrorVectors.load()
        let k = try keys(v)
        let sealed = try XCTUnwrap(Base64URL.decode(v.item.expectedSealed))
        func flipped(_ index: Int) -> Data { var copy = sealed; copy[index] ^= 1; return copy }
        for index in [0, 14, sealed.count - 1] {
            XCTAssertThrowsError(try MirrorCrypto.openItem(keys: k, itemID: v.id.expected, sealed: flipped(index))) {
                XCTAssertEqual($0 as? MirrorCrypto.Failure, .authentication)
            }
        }
        XCTAssertThrowsError(try MirrorCrypto.openItem(keys: k, itemID: "other", sealed: sealed)) {
            XCTAssertEqual($0 as? MirrorCrypto.Failure, .authentication)
        }
        XCTAssertThrowsError(try MirrorCrypto.openItem(keys: k, itemID: v.id.expected, sealed: sealed.prefix(10))) {
            XCTAssertEqual($0 as? MirrorCrypto.Failure, .malformed)
        }
    }

    func testDataKeyMustBe32Bytes() {
        for count in [0, 16, 31, 33, 64] { XCTAssertNil(MirrorKeys(dataKey: Data(count: count)), "\(count)") }
    }

    func testAgreementMatchesVectorFromBothSides() throws {
        let v = try MirrorVectors.load()
        let nonce = Data(hex: v.pair.nonceHex)
        let phone = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.pair.phonePrivHex))
        let browser = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.pair.browserPrivHex))
        XCTAssertEqual(phone.publicKey.x963Representation, Data(hex: v.pair.phonePubHex))
        let fromPhone = try MirrorCrypto.agree(privateKey: phone, otherPublic: Data(hex: v.pair.browserPubHex), nonce: nonce)
        let fromBrowser = try MirrorCrypto.agree(privateKey: browser, otherPublic: Data(hex: v.pair.phonePubHex), nonce: nonce)
        let raw = { (key: SymmetricKey) in key.withUnsafeBytes { Data($0) } }
        XCTAssertEqual(raw(fromPhone), Data(hex: v.pair.kPairHex))
        XCTAssertEqual(raw(fromBrowser), Data(hex: v.pair.kPairHex))
    }

    func testAgreementRejectsBadKeysAndNonces() throws {
        let v = try MirrorVectors.load()
        let phone = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.pair.phonePrivHex))
        let nonce = Data(hex: v.pair.nonceHex)
        let good = Data(hex: v.pair.browserPubHex)
        var offCurve = good
        offCurve[64] ^= 1
        var compressed = good
        compressed[0] = 2
        for (name, key, n) in [("64 bytes", good.prefix(64), nonce), ("prefix 2", compressed, nonce), ("off curve", offCurve, nonce), ("short nonce", good, nonce.prefix(8))] {
            XCTAssertThrowsError(try MirrorCrypto.agree(privateKey: phone, otherPublic: Data(key), nonce: Data(n)), name) {
                XCTAssertEqual($0 as? MirrorCrypto.Failure, .badKey, name)
            }
        }
    }

    func testMatchCodeMatchesVector() throws {
        let v = try MirrorVectors.load()
        XCTAssertEqual(MirrorCrypto.matchCode(browserPublic: Data(hex: v.pair.browserPubHex), phonePublic: Data(hex: v.pair.phonePubHex), nonce: Data(hex: v.pair.nonceHex)), v.pair.matchCode)
    }

    func testWrapReproducesVectorAndRoundTrips() throws {
        let v = try MirrorVectors.load()
        let key = SymmetricKey(data: Data(hex: v.pair.kPairHex))
        let sealed = try MirrorCrypto.sealWrap(key: key, pairID: v.pair.pairId, plaintext: Data(v.wrap.plaintextUtf8.utf8), iv: Data(hex: v.wrap.ivHex))
        XCTAssertEqual(Base64URL.encode(sealed), v.wrap.expectedSealed)
        XCTAssertEqual(String(decoding: try MirrorCrypto.openWrap(key: key, pairID: v.pair.pairId, sealed: sealed), as: UTF8.self), v.wrap.plaintextUtf8)
        XCTAssertThrowsError(try MirrorCrypto.openWrap(key: key, pairID: "otherPair", sealed: sealed))
    }

    func testRotationBlobReproducesTheVectorAndOpens() throws {
        let r = try MirrorVectors.load().rotation
        let sealed = try MirrorCrypto.sealRotation(deviceKey: Data(hex: r.deviceKeyHex), mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch, dataKey: Data(hex: r.newDataKeyHex), iv: Data(hex: r.ivHex))
        XCTAssertEqual(Base64URL.encode(sealed), r.expectedSealed)
        let opened = try MirrorCrypto.openRotation(deviceKey: Data(hex: r.deviceKeyHex), mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch, sealed: sealed)
        XCTAssertEqual(opened, Data(hex: r.newDataKeyHex))
        XCTAssertEqual(r.plaintextUtf8, #"{"v":1,"epoch":3,"dataKey":"\#(Base64URL.encode(Data(hex: r.newDataKeyHex)))"}"#)
    }

    func testRotationBlobFailsForAnythingElse() throws {
        let r = try MirrorVectors.load().rotation
        let key = Data(hex: r.deviceKeyHex)
        let sealed = try XCTUnwrap(Base64URL.decode(r.expectedSealed))
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: key, mirrorID: "OTHER", deviceID: r.deviceId, epoch: r.epoch, sealed: sealed))
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: key, mirrorID: r.mirrorId, deviceID: "OTHER", epoch: r.epoch, sealed: sealed))
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: key, mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch + 1, sealed: sealed))
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: Data(repeating: 1, count: 32), mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch, sealed: sealed))
        var flipped = sealed
        flipped[20] ^= 1
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: key, mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch, sealed: flipped))
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: key, mirrorID: r.mirrorId, deviceID: r.deviceId, epoch: r.epoch, sealed: Data(count: 27)))
        // inputs the protocol forbids are refused before anything is sealed
        XCTAssertThrowsError(try MirrorCrypto.sealRotation(deviceKey: Data(count: 31), mirrorID: "m", deviceID: "d", epoch: 1, dataKey: Data(count: 32)))
        XCTAssertThrowsError(try MirrorCrypto.sealRotation(deviceKey: key, mirrorID: "m", deviceID: "d", epoch: 0, dataKey: Data(count: 32)))
    }

    func testBase64URLIsStrictAndRoundTrips() {
        for bad in ["ab=", "a+b", "a/b", "a b", "a"] { XCTAssertNil(Base64URL.decode(bad), bad) }
        for count in 0...40 {
            let data = MirrorCrypto.randomBytes(count)
            let text = Base64URL.encode(data)
            XCTAssertFalse(text.contains("=") || text.contains("+") || text.contains("/"))
            XCTAssertEqual(Base64URL.decode(text), data)
        }
    }

    func testSHA256Hex() {
        XCTAssertEqual(MirrorCrypto.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(MirrorCrypto.sha256Hex("").count, 64)
    }

    func testRandomBytesDiffer() {
        XCTAssertNotEqual(MirrorCrypto.randomBytes(32), MirrorCrypto.randomBytes(32))
        XCTAssertEqual(MirrorCrypto.randomBytes(32).count, 32)
    }
}
