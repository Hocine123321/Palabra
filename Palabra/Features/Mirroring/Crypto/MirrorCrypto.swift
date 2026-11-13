import CryptoKit
import Foundation

/// Unpadded base64url. Anything outside the alphabet, "=" included, is rejected.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }), text.count % 4 != 1 else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard)
    }
}

/// The two keys derived from the 32-byte data key (protocol v1): `aes` seals and opens items, `id` names them.
struct MirrorKeys {
    let aes: SymmetricKey
    let id: SymmetricKey

    /// nil unless `dataKey` is exactly 32 bytes.
    init?(dataKey: Data) {
        guard dataKey.count == 32 else { return nil }
        let input = SymmetricKey(data: dataKey)
        aes = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: Data(), info: Data("palabra-mirror-aes-v1".utf8), outputByteCount: 32)
        id = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: Data(), info: Data("palabra-mirror-id-key-v1".utf8), outputByteCount: 32)
    }

    static func randomDataKey() -> Data { MirrorCrypto.randomBytes(32) }
}

/// Protocol v1 primitives. Every value is checked against `mirror-vectors.json` in the tests.
enum MirrorCrypto {
    enum Failure: Error, Equatable { case malformed, authentication, badKey }

    private static let ivBytes = 12
    private static let tagBytes = 16

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// Lowercase hex SHA-256 of the UTF-8 text: the only form of a token the Worker ever sees.
    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Items

    static func itemID(keys: MirrorKeys, kind: String, recordID: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(kind)|\(recordID)".utf8), using: keys.id)
        return Base64URL.encode(Data(mac).prefix(16))
    }

    static func sealItem(keys: MirrorKeys, itemID: String, plaintext: Data, iv: Data? = nil) throws -> Data {
        try seal(key: keys.aes, aad: "palabra-mirror-item-v1|\(itemID)", plaintext: plaintext, iv: iv)
    }

    static func openItem(keys: MirrorKeys, itemID: String, sealed: Data) throws -> Data {
        try open(key: keys.aes, aad: "palabra-mirror-item-v1|\(itemID)", sealed: sealed)
    }

    // MARK: Pairing

    /// ECDH P-256, then HKDF with the nonce as salt. The result is the AES key that wraps the secrets.
    static func agree(privateKey: P256.KeyAgreement.PrivateKey, otherPublic: Data, nonce: Data) throws -> SymmetricKey {
        guard otherPublic.count == 65, otherPublic.first == 4, nonce.count == 16 else { throw Failure.badKey }
        guard let publicKey = try? P256.KeyAgreement.PublicKey(x963Representation: otherPublic),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: publicKey) else { throw Failure.badKey }
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: nonce, sharedInfo: Data("palabra-mirror-pair-v1".utf8), outputByteCount: 32)
    }

    /// Four digits both screens show. A person compares them before anything is released.
    static func matchCode(browserPublic: Data, phonePublic: Data, nonce: Data) -> String {
        let digest = Array(SHA256.hash(data: browserPublic + phonePublic + nonce))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%04u", value % 10000)
    }

    static func sealWrap(key: SymmetricKey, pairID: String, plaintext: Data, iv: Data? = nil) throws -> Data {
        try seal(key: key, aad: "palabra-mirror-wrap-v1|\(pairID)", plaintext: plaintext, iv: iv)
    }

    static func openWrap(key: SymmetricKey, pairID: String, sealed: Data) throws -> Data {
        try open(key: key, aad: "palabra-mirror-wrap-v1|\(pairID)", sealed: sealed)
    }

    // MARK: Key rotation

    /// The new data key sealed to one computer under its device key: `iv | ciphertext | tag` over
    /// `{"v":1,"epoch":<n>,"dataKey":"<base64url>"}`, bound to the mirror, the device and the epoch.
    static func sealRotation(deviceKey: Data, mirrorID: String, deviceID: String, epoch: Int, dataKey: Data, iv: Data? = nil) throws -> Data {
        guard deviceKey.count == 32, dataKey.count == 32, epoch >= 1 else { throw Failure.badKey }
        // Written by hand so the bytes are the same as the protocol vectors', whatever the JSON encoder's key order.
        let plaintext = Data(#"{"v":1,"epoch":\#(epoch),"dataKey":"\#(Base64URL.encode(dataKey))"}"#.utf8)
        return try seal(key: SymmetricKey(data: deviceKey), aad: rotationAAD(mirrorID: mirrorID, deviceID: deviceID, epoch: epoch), plaintext: plaintext, iv: iv)
    }

    /// The reverse of `sealRotation`; the epoch inside must be the one asked for. Used by the tests (the page does this in JavaScript).
    static func openRotation(deviceKey: Data, mirrorID: String, deviceID: String, epoch: Int, sealed: Data) throws -> Data {
        guard deviceKey.count == 32 else { throw Failure.badKey }
        let plain = try open(key: SymmetricKey(data: deviceKey), aad: rotationAAD(mirrorID: mirrorID, deviceID: deviceID, epoch: epoch), sealed: sealed)
        guard let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              object["v"] as? Int == 1, object["epoch"] as? Int == epoch,
              let text = object["dataKey"] as? String, let key = Base64URL.decode(text), key.count == 32 else { throw Failure.malformed }
        return key
    }

    private static func rotationAAD(mirrorID: String, deviceID: String, epoch: Int) -> String {
        "palabra-mirror-rotate-v1|\(mirrorID)|\(deviceID)|\(epoch)"
    }

    // MARK: AES-GCM as iv | ciphertext | tag

    private static func seal(key: SymmetricKey, aad: String, plaintext: Data, iv: Data?) throws -> Data {
        let nonce: AES.GCM.Nonce
        if let iv {
            guard iv.count == ivBytes, let made = try? AES.GCM.Nonce(data: iv) else { throw Failure.malformed }
            nonce = made
        } else {
            nonce = AES.GCM.Nonce()
        }
        guard let box = try? AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: Data(aad.utf8)),
              let combined = box.combined else { throw Failure.malformed }
        return combined
    }

    private static func open(key: SymmetricKey, aad: String, sealed: Data) throws -> Data {
        guard sealed.count >= ivBytes + tagBytes, let box = try? AES.GCM.SealedBox(combined: sealed) else { throw Failure.malformed }
        guard let plain = try? AES.GCM.open(box, using: key, authenticating: Data(aad.utf8)) else { throw Failure.authentication }
        return plain
    }
}
