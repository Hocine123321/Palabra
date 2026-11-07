import Foundation

/// The phone's side of the pairing hop, with no networking in it: the listener feeds it requests, it answers.
/// Protocol (all JSON, over the direct local connection only):
///   GET  /hello            -> {protocol, nonce}                      (a fresh nonce; the page keeps it)
///   POST /pair {nonce, proof} -> {iv, sealed}                        (right code) | {error: "wrong"|"locked", ...}
final class PairingService: @unchecked Sendable {
    struct Config: Sendable {
        var nonceLifetime: TimeInterval = 120
        var maxOpenNonces = 8
    }

    enum Reply: Equatable, Sendable {
        case hello(nonce: Data)
        case paired(iv: Data, sealed: Data)
        case wrong(triesLeft: Int)
        case locked(seconds: Int)
        case badRequest
    }

    private let lock = NSLock()
    private let config: Config
    private let now: @Sendable () -> Date
    private let persist: @Sendable (PairingLockout) -> Void
    private var lockout: PairingLockout
    private var nonces: [Data: Date] = [:]
    private var code: String?
    private var secret: Data?

    /// Called with the new session secret after a right code; the app stores it (Keychain) and returns whether that worked.
    /// If it did not, the page is told the pairing failed instead of being handed a secret the phone does not have.
    var onPaired: (@Sendable (Data) -> Bool)?

    init(lockout: PairingLockout = PairingLockout(),
         config: Config = Config(),
         now: @escaping @Sendable () -> Date = { Date() },
         persist: @escaping @Sendable (PairingLockout) -> Void = { _ in }) {
        self.lockout = lockout
        self.config = config
        self.now = now
        self.persist = persist
    }

    static func isAcceptableCode(_ code: String) -> Bool {
        code.count >= 6 && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Opens pairing with a code the person chose (>= 6 digits). A new code and a new secret each time.
    @discardableResult
    func open(code: String) -> Bool {
        guard Self.isAcceptableCode(code) else { return false }
        lock.lock(); defer { lock.unlock() }
        self.code = code
        secret = LinkCrypto.randomBytes(LinkCrypto.secretBytes)
        nonces.removeAll()
        return true
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        code = nil; secret = nil; nonces.removeAll()
    }

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return code != nil }
    var currentLockout: PairingLockout { lock.lock(); defer { lock.unlock() }; return lockout }

    func hello() -> Reply {
        lock.lock(); defer { lock.unlock() }
        guard code != nil else { return .badRequest }
        let t = now()
        // Say so up front, so the page shows the wait before the person types a code.
        if lockout.isLocked(now: t) { return .locked(seconds: Int(lockout.remaining(now: t).rounded(.up))) }
        nonces = nonces.filter { t.timeIntervalSince($0.value) < config.nonceLifetime }
        if nonces.count >= config.maxOpenNonces { return .badRequest }
        let nonce = LinkCrypto.randomBytes(16)
        nonces[nonce] = t
        return .hello(nonce: nonce)
    }

    func pair(nonce: Data, proof: Data) -> Reply {
        lock.lock()
        let t = now()
        guard let code, let secret else { lock.unlock(); return .badRequest }
        if lockout.isLocked(now: t) {
            let wait = Int(lockout.remaining(now: t).rounded(.up))
            lock.unlock(); return .locked(seconds: wait)
        }
        // A nonce works once, even for a wrong proof, so one nonce is one guess.
        guard let issued = nonces.removeValue(forKey: nonce), t.timeIntervalSince(issued) < config.nonceLifetime else {
            lock.unlock(); return .badRequest
        }
        if LinkCrypto.isValidProof(proof, code: code, nonce: nonce) {
            lockout.recordSuccess()
            let snapshot = lockout
            self.code = nil; self.secret = nil; nonces.removeAll()
            lock.unlock()
            persist(snapshot)
            do {
                let wrapped = try LinkCrypto.wrapSecret(code: code, nonce: nonce, secret: secret)
                guard onPaired?(secret) ?? true else { return .badRequest }
                return .paired(iv: wrapped.iv, sealed: wrapped.sealed)
            } catch {
                return .badRequest
            }
        }
        let started = lockout.recordWrong(now: t)
        let snapshot = lockout
        let left = PairingLockout.triesBeforeLockout - lockout.wrongInRow
        lock.unlock()
        persist(snapshot)
        if let started { return .locked(seconds: Int(started)) }
        return .wrong(triesLeft: left)
    }
}
