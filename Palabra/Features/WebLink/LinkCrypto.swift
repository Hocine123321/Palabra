import CryptoKit
import Foundation
import Security

/// The crypto of the web link, protocol v1. It must match `web/src/link-crypto.js` byte for byte;
/// `LinkCryptoTests` pins both to the same fixed vectors.
enum LinkCrypto {
    static let secretBytes = 32

    private static func hkdf(_ ikm: Data, salt: Data, info: String, count: Int) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: count
        )
    }

    private static func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// What the page must send to prove it knows the code, without sending the code.
    static func pairingProof(code: String, nonce: Data) -> Data {
        let key = hkdf(Data(code.utf8), salt: nonce, info: "palabra-proof-v1", count: 32)
        return Data(HMAC<SHA256>.authenticationCode(for: nonce, using: key))
    }

    /// Constant-time check of a proof from the page.
    static func isValidProof(_ proof: Data, code: String, nonce: Data) -> Bool {
        let expected = pairingProof(code: code, nonce: nonce)
        guard proof.count == expected.count else { return false }
        return zip(proof, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// Seals the session secret so only someone who knows the code can open it. Returns iv, then ciphertext and tag.
    static func wrapSecret(code: String, nonce: Data, secret: Data, iv: Data? = nil) throws -> (iv: Data, sealed: Data) {
        let key = hkdf(Data(code.utf8), salt: nonce, info: "palabra-wrap-v1", count: 32)
        let gcmNonce: AES.GCM.Nonce
        if let iv { gcmNonce = try AES.GCM.Nonce(data: iv) } else { gcmNonce = AES.GCM.Nonce() }
        let sealedBox = try AES.GCM.seal(secret, using: key, nonce: gcmNonce, authenticating: nonce)
        return (Data(sealedBox.nonce), sealedBox.ciphertext + sealedBox.tag)
    }

    /// The relay room id, derived from the secret so the relay never learns the code or the secret.
    static func roomID(secret: Data) -> String {
        bytes(hkdf(secret, salt: Data(), info: "palabra-room-v1", count: 16)).map { String(format: "%02x", $0) }.joined()
    }

    /// Key material and nonces come from the system's secure generator.
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "secure random failed")
        return Data(bytes)
    }

    // MARK: Session frames

    enum Role: UInt8 {
        case app = 0x41
        case web = 0x57
        var peer: Role { self == .app ? .web : .app }
    }

    enum FrameError: Error, Equatable { case short, bad, replayed }

    /// One end of the encrypted link. Frame: iv(12) | counter(8, big endian) | ciphertext+tag.
    /// The role and counter are authenticated, so a frame cannot be reflected or replayed.
    final class Session: @unchecked Sendable {
        private let key: SymmetricKey
        let role: Role
        private let lock = NSLock()
        private var sendCounter: UInt64 = 0
        private var lastReceived: Int64 = -1

        init(secret: Data, role: Role) {
            self.key = LinkCrypto.hkdf(secret, salt: Data(), info: "palabra-aead-v1", count: 32)
            self.role = role
        }

        private static func aad(_ role: Role, _ counter: UInt64) -> Data {
            var data = Data([role.rawValue])
            withUnsafeBytes(of: counter.bigEndian) { data.append(contentsOf: $0) }
            return data
        }

        func seal(_ message: Data) throws -> Data {
            lock.lock(); let counter = sendCounter; sendCounter += 1; lock.unlock()
            let box = try AES.GCM.seal(message, using: key, nonce: AES.GCM.Nonce(), authenticating: Self.aad(role, counter))
            var out = Data(box.nonce)
            withUnsafeBytes(of: counter.bigEndian) { out.append(contentsOf: $0) }
            out.append(box.ciphertext)
            out.append(box.tag)
            return out
        }

        func open(_ frame: Data) throws -> Data {
            guard frame.count >= 12 + 8 + 16 else { throw FrameError.short }
            let bytes = [UInt8](frame)
            let counter = bytes[12..<20].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let body = Array(bytes[20...])
            let plain: Data
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: AES.GCM.Nonce(data: bytes[0..<12]),
                    ciphertext: body.dropLast(16),
                    tag: body.suffix(16)
                )
                plain = try AES.GCM.open(box, using: key, authenticating: Self.aad(role.peer, counter))
            } catch {
                throw FrameError.bad
            }
            lock.lock(); defer { lock.unlock() }
            guard Int64(clamping: counter) > lastReceived else { throw FrameError.replayed }
            lastReceived = Int64(clamping: counter)
            return plain
        }
    }
}
