import CryptoKit
import Foundation

/// Automatic pairing, phone side: the crypto that must agree with `web/src/trust-crypto.js` byte for byte.
/// Both ends make a one-time P-256 key pair and swap the public halves through the lobby. The match code and the shared key
/// both depend on BOTH public keys, so a man in the middle who swaps one shows a different code and gets a different key.
/// After the person taps Trust, the phone seals the link secret, a trust token and its relay address under that key.
enum TrustCrypto {
    static let publicKeyBytes = 65
    static let tokenBytes = 32

    enum TrustError: Error, Equatable { case badPublicKey, badGrant }

    /// A one-time key pair for one attempt.
    struct Keys {
        let privateKey: P256.KeyAgreement.PrivateKey
        var publicHex: String { privateKey.publicKey.x963Representation.hex }
        init() { privateKey = P256.KeyAgreement.PrivateKey() }
        init(privateKey: P256.KeyAgreement.PrivateKey) { self.privateKey = privateKey }
    }

    /// Only an uncompressed P-256 point is accepted; anything else is refused before any math.
    static func publicKey(hex: String) throws -> P256.KeyAgreement.PublicKey {
        guard let bytes = Data(hexString: hex), bytes.count == publicKeyBytes, bytes.first == 4,
              let key = try? P256.KeyAgreement.PublicKey(x963Representation: bytes) else { throw TrustError.badPublicKey }
        return key
    }

    private static func sha256(_ parts: Data...) -> Data {
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }

    /// Four digits both screens show. Same digits only if both ends saw each other's real public keys.
    static func matchCode(phonePub: String, browserPub: String) throws -> String {
        let phone = try publicKey(hex: phonePub).x963Representation
        let browser = try publicKey(hex: browserPub).x963Representation
        let digest = sha256(Data("palabra-match-v1".utf8), phone, browser)
        let n = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%04d", n % 10_000)
    }

    private static func sharedKey(mine: P256.KeyAgreement.PrivateKey, theirPub: String, phonePub: String, browserPub: String) throws -> SymmetricKey {
        let theirs = try publicKey(hex: theirPub)
        let phone = try publicKey(hex: phonePub).x963Representation
        let browser = try publicKey(hex: browserPub).x963Representation
        let secret = try mine.sharedSecretFromKeyAgreement(with: theirs)
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: sha256(phone, browser),
                                              sharedInfo: Data("palabra-trust-v1".utf8), outputByteCount: 32)
    }

    /// Layout: secret(32) | token(32) | relay address (UTF-8, the rest).
    static func packGrant(secret: Data, token: Data, relayURL: String) throws -> Data {
        guard secret.count == LinkCrypto.secretBytes, token.count == tokenBytes else { throw TrustError.badGrant }
        return secret + token + Data(relayURL.trimmingCharacters(in: .whitespacesAndNewlines).utf8.prefix(200))
    }

    struct Grant: Equatable { let secret: Data; let token: Data; let relayURL: String }

    static func unpackGrant(_ bytes: Data) throws -> Grant {
        guard bytes.count >= LinkCrypto.secretBytes + tokenBytes else { throw TrustError.badGrant }
        let all = [UInt8](bytes)
        let secret = Data(all[0..<LinkCrypto.secretBytes])
        let token = Data(all[LinkCrypto.secretBytes..<(LinkCrypto.secretBytes + tokenBytes)])
        let relay = String(decoding: all[(LinkCrypto.secretBytes + tokenBytes)...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Grant(secret: secret, token: token, relayURL: relay)
    }

    /// Phone side: seal a grant for the browser that asked. Returns iv, then ciphertext and tag.
    static func sealGrant(phone: Keys, browserPub: String, secret: Data, token: Data, relayURL: String, iv: Data? = nil) throws -> (iv: Data, sealed: Data) {
        let key = try sharedKey(mine: phone.privateKey, theirPub: browserPub, phonePub: phone.publicHex, browserPub: browserPub)
        let nonce: AES.GCM.Nonce
        if let iv { nonce = try AES.GCM.Nonce(data: iv) } else { nonce = AES.GCM.Nonce() }
        let box = try AES.GCM.seal(try packGrant(secret: secret, token: token, relayURL: relayURL), using: key, nonce: nonce,
                                   authenticating: Data("palabra-grant-v1".utf8))
        return (Data(box.nonce), box.ciphertext + box.tag)
    }

    /// The inverse, as the browser does it. The app never needs it; tests use it to check what really travels.
    static func openGrant(browser: Keys, phonePub: String, iv: Data, sealed: Data) throws -> Grant {
        let key = try sharedKey(mine: browser.privateKey, theirPub: phonePub, phonePub: phonePub, browserPub: browser.publicHex)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        return try unpackGrant(try AES.GCM.open(box, using: key, authenticating: Data("palabra-grant-v1".utf8)))
    }

    /// The token is kept only as a hash, so a stolen phone backup does not hold a usable token.
    static func tokenHash(_ token: Data) -> String {
        sha256(Data("palabra-token-v1".utf8), token).hex
    }
}
