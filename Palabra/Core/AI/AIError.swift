import Foundation

/// Every way a Google AI call, or the content it returns, can fail — with the message,
/// retryability, and suggested recovery the UI needs. Never constructed from guesswork:
/// each case documents the exact trigger in the design spec (§7 error taxonomy).
enum AIError: Error, Equatable, Sendable {
    case missingAPIKey
    case noModelSelected
    case modelUnavailable(String)
    case offline
    case timeout
    case invalidAPIKey
    case permissionDenied
    case rateLimited
    /// Daily / billing quota is used up: waiting minutes will not help.
    case quotaExhausted
    case serverError(Int)
    case blocked(String?)
    case truncated
    case malformedResponse
    case validationFailed([String])
    case emptyCatalogue
    case unknown(Int?, String)

    enum Recovery: Equatable, Sendable {
        case retry
        case openSettings
        case chooseModel
    }

    var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .noModelSelected, .modelUnavailable, .invalidAPIKey, .permissionDenied, .blocked:
            return false
        case .offline, .timeout, .rateLimited, .serverError, .truncated, .malformedResponse, .validationFailed, .emptyCatalogue, .unknown:
            return true
        case .quotaExhausted:
            return false
        }
    }

    var recovery: Recovery? {
        switch self {
        case .missingAPIKey, .invalidAPIKey, .permissionDenied, .quotaExhausted:
            return .openSettings
        case .noModelSelected, .modelUnavailable, .emptyCatalogue:
            return .chooseModel
        case .offline, .timeout, .rateLimited, .serverError, .truncated, .malformedResponse, .validationFailed, .unknown:
            return .retry
        case .blocked:
            return nil
        }
    }

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "Add your Google API key in Settings to use AI features."
        case .noModelSelected:
            return "Choose a Google AI model in Settings."
        case .modelUnavailable(let id):
            return "The model \"\(id)\" is no longer available. Choose another in Settings."
        case .offline:
            return "You're offline. Check your connection and try again."
        case .timeout:
            return "The request took too long. Try again."
        case .invalidAPIKey:
            return "That API key isn't valid. Check it in Settings."
        case .permissionDenied:
            return "Your API key doesn't have permission for this request."
        case .rateLimited:
            return "You've hit Google's rate limit. Wait a moment and try again."
        case .quotaExhausted:
            return "This API key has used up its quota. Add a fallback key in Settings, or try again later."
        case .serverError:
            return "Google's servers had a problem. Try again in a bit."
        case .blocked(let reason):
            if let reason, !reason.isEmpty {
                return "The response was blocked (\(reason))."
            }
            return "The response was blocked."
        case .truncated:
            return "The response was cut off before it finished. Try again."
        case .malformedResponse:
            return "The AI response couldn't be read. Try again."
        case .validationFailed:
            return "The AI response was incomplete. Try again."
        case .emptyCatalogue:
            return "Google didn't return any usable models."
        case .unknown(_, let message):
            return message.isEmpty ? "Something went wrong. Try again." : message
        }
    }
}
