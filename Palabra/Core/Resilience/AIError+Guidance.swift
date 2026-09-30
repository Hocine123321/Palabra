import Foundation

/// The wording and choices the app offers for each failure. Kept next to the strategy
/// (not in the views) so the advice stays consistent and testable.
extension AIError {
    /// A few words, for the retry status line.
    var shortReason: String {
        switch self {
        case .offline: return "No connection"
        case .timeout: return "The request timed out"
        case .rateLimited: return "Too many requests"
        case .quotaExhausted: return "Quota used up"
        case .serverError: return "Google had a problem"
        case .truncated: return "The reply was cut off"
        case .malformedResponse, .validationFailed: return "The reply was incomplete"
        case .invalidAPIKey: return "Key rejected"
        case .permissionDenied: return "Key not allowed"
        default: return "Something went wrong"
        }
    }

    var headline: String {
        switch self {
        case .rateLimited: return "Google is asking us to slow down"
        case .quotaExhausted: return "This API key is out of quota"
        case .invalidAPIKey: return "Your API key was rejected"
        case .permissionDenied: return "Your API key isn't allowed to do this"
        case .offline: return "You're offline"
        case .timeout: return "Google is taking too long"
        case .serverError: return "Google's servers are struggling"
        case .modelUnavailable: return "Your chosen model is gone"
        case .blocked: return "The request was blocked"
        default: return "This didn't work"
        }
    }

    /// Whether waiting longer can plausibly fix it. False for problems only the person
    /// (or another key) can solve, so the app doesn't offer a pointless option.
    var canBenefitFromWaiting: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout, .truncated, .malformedResponse, .validationFailed, .unknown, .emptyCatalogue, .offline:
            return true
        default:
            return false
        }
    }

    func explanation(tried attempts: Int, hasBackupKey: Bool) -> String {
        let tried = attempts > 0 ? "I tried \(attempts) time\(attempts == 1 ? "" : "s") already. " : ""
        switch self {
        case .rateLimited:
            return tried + (hasBackupKey ? "The backup key is limited too. Waiting a bit usually clears it." : "Waiting a bit usually clears it. A backup key from another account would avoid the wait.")
        case .quotaExhausted:
            return hasBackupKey ? "Both keys are out of quota. Try again later, or use a key from another account."
                                : "Waiting won't help until the quota resets. Add a key from another account in Settings to keep going."
        case .invalidAPIKey:
            return "Google doesn't accept this key. Check it in Settings, or add a backup key."
        case .permissionDenied:
            return "This key can't use that model. Pick another model, or use a different key."
        case .serverError, .timeout:
            return tried + "This is usually temporary on Google's side. Waiting longer between tries often works."
        case .modelUnavailable(let id):
            return "The model \"\(id)\" no longer exists. Choose another one in Settings."
        case .blocked:
            return "Google's safety filter blocked this. Trying again won't change that."
        default:
            return tried + "It may work on another try."
        }
    }

    var settingsButtonTitle: String {
        switch self {
        case .quotaExhausted, .rateLimited: return "Add a Backup Key"
        case .modelUnavailable, .noModelSelected: return "Choose a Model"
        default: return "Open Settings"
        }
    }
}
