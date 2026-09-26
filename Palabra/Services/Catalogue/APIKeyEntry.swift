import Foundation

/// Validates a candidate API key by fetching the model catalogue with it,
/// then decides whether to save it. Only a confirmed-invalid key is
/// rejected; every other failure (offline, rate limited, ...) still saves
/// the key with a warning, since the key itself may be fine (spec §8).
enum APIKeyEntry {
    enum Outcome: Equatable {
        case invalid
        case saved
        case savedWithWarning(AIError)
    }

    @MainActor
    static func verifyAndSave(_ rawKey: String, environment: AppEnvironment) async -> Outcome {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        await environment.catalogue.refresh(apiKey: trimmed, using: environment.ai)

        if case .failed(.invalidAPIKey, _) = environment.catalogue.status {
            return .invalid
        }

        environment.saveAPIKey(trimmed)
        if environment.selectedModelID == nil {
            environment.selectedModelID = DefaultModelPicker.pick(from: environment.catalogue.models)?.id
        }

        if case .failed(let error, _) = environment.catalogue.status {
            return .savedWithWarning(error)
        }
        return .saved
    }
}
