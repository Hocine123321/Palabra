import Foundation

/// What the app does about each kind of AI failure. Pure and deterministic so every
/// reaction can be unit tested: no clocks, no network, no randomness.
///
/// The idea: different failures need different reactions. Waiting fixes a rate limit
/// but never a spent quota; another key fixes a spent quota or a bad key but not a
/// server outage; nothing fixes a blocked prompt.
enum ErrorStrategy {
    /// The single next step for a failure.
    enum Action: Equatable, Sendable {
        /// Wait, then try again with the same key.
        case retry(after: TimeInterval)
        /// Wait until the network is back (does not use up an attempt), then try again.
        case waitForNetwork
        /// Abandon this key and use the fallback key, if there is one.
        case switchKey
        /// Ask the user (nothing more can be done automatically).
        case askUser
        /// Stop and explain. Trying again cannot help (e.g. a blocked prompt).
        case giveUp
    }

    /// How a failure relates to the key that was used.
    enum Blame: Equatable, Sendable {
        /// Only this key/account is at fault: a fallback key can help.
        case key
        /// Network or Google is at fault: a different key will not help.
        case transient
        /// The request itself is at fault: nothing automatic can help.
        case request
        /// Setup problem the user must fix (no key, no model).
        case setup
    }

    static func blame(_ error: AIError) -> Blame {
        switch error {
        case .invalidAPIKey, .permissionDenied, .quotaExhausted, .rateLimited:
            return .key
        case .offline, .timeout, .serverError, .truncated, .malformedResponse, .validationFailed, .unknown, .emptyCatalogue:
            return .transient
        case .blocked:
            return .request
        case .missingAPIKey, .noModelSelected, .modelUnavailable:
            return .setup
        }
    }

    /// Maximum automatic attempts on one key, for a given failure. A rate limit is
    /// worth a couple of patient tries; a malformed reply is usually a one-off.
    static func maxAttempts(for error: AIError, policy: RetryPolicy) -> Int {
        switch error {
        case .rateLimited: return policy.maxAutomaticAttempts
        case .serverError, .timeout: return policy.maxAutomaticAttempts
        case .truncated, .malformedResponse, .validationFailed, .unknown, .emptyCatalogue: return min(2, policy.maxAutomaticAttempts)
        default: return 0
        }
    }

    /// What to do after `failedAttempts` failed tries on the current key.
    /// - Parameters:
    ///   - serverHint: a `retryDelay` the server asked for, if any.
    ///   - hasFallback: another key is available and not itself known to be failing.
    static func next(
        after error: AIError,
        failedAttempts: Int,
        policy: RetryPolicy,
        hasFallback: Bool,
        serverHint: TimeInterval? = nil
    ) -> Action {
        switch error {
        case .offline:
            return .waitForNetwork
        case .blocked, .missingAPIKey, .noModelSelected:
            return .giveUp
        case .modelUnavailable:
            return .askUser
        case .invalidAPIKey, .permissionDenied, .quotaExhausted:
            // Waiting never fixes these; only a different key can.
            return hasFallback ? .switchKey : .askUser
        default:
            break
        }
        if failedAttempts < maxAttempts(for: error, policy: policy) {
            let base = policy.delay(forAttempt: failedAttempts)
            // Honor the server's own hint, but never wait unreasonably long automatically.
            let wait = min(max(base, serverHint ?? 0), policy.maxAutomaticWait)
            return .retry(after: wait)
        }
        // Out of automatic attempts on this key. A different key can help when the
        // trouble is tied to the key (rate limit) or, for an outage or timeouts,
        // may simply be routed better. Anything else needs the user.
        return canBenefitFromOtherKey(error) && hasFallback ? .switchKey : .askUser
    }

    private static func canBenefitFromOtherKey(_ error: AIError) -> Bool {
        if blame(error) == .key { return true }
        return isServerSide(error)
    }

    private static func isServerSide(_ error: AIError) -> Bool {
        if case .serverError = error { return true }
        return error == .timeout
    }
}

/// The user's retry preferences. Backoff doubles each try, capped.
struct RetryPolicy: Equatable, Codable, Sendable {
    /// Automatic tries on one key before asking the user or switching key.
    var maxAutomaticAttempts: Int = 3
    /// First wait, in seconds.
    var baseDelay: TimeInterval = 2
    /// Automatic waits never exceed this. Beyond it, the user is asked.
    var maxAutomaticWait: TimeInterval = 30
    /// When the user picks "retry with longer waits", every wait is multiplied by this.
    var patientMultiplier: Double = 4
    /// Master switch: when off, every failure goes straight to the user, as before.
    var autoRetryEnabled: Bool = true

    static let `default` = RetryPolicy()

    /// 2s, 4s, 8s, ... capped at `maxAutomaticWait`.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exp = baseDelay * pow(2, Double(max(attempt, 0)))
        return min(exp, maxAutomaticWait)
    }

    /// The "patient" schedule offered after automatic retries fail: same backoff
    /// stretched by `patientMultiplier`, with a much higher ceiling.
    func patientDelay(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2, Double(max(attempt, 0))) * patientMultiplier, 300)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RetryPolicy()
        maxAutomaticAttempts = min(max(try c.decodeIfPresent(Int.self, forKey: .maxAutomaticAttempts) ?? d.maxAutomaticAttempts, 0), 6)
        baseDelay = min(max(try c.decodeIfPresent(TimeInterval.self, forKey: .baseDelay) ?? d.baseDelay, 0.5), 30)
        maxAutomaticWait = min(max(try c.decodeIfPresent(TimeInterval.self, forKey: .maxAutomaticWait) ?? d.maxAutomaticWait, 1), 120)
        patientMultiplier = min(max(try c.decodeIfPresent(Double.self, forKey: .patientMultiplier) ?? d.patientMultiplier, 1), 20)
        autoRetryEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoRetryEnabled) ?? d.autoRetryEnabled
    }
}
