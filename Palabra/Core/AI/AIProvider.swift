import Foundation

/// Who answers the AI requests. Gemini is the original and the only one that can speak (pronunciation); OpenRouter and Groq
/// speak the OpenAI-style chat protocol, so one client (`OpenAICompatibleClient`) serves both. Every provider uses the
/// person's own key.
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini
    case openRouter
    case groq

    var id: String { rawValue }

    /// A localization key.
    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        }
    }

    /// The label of the key field (a localization key).
    var keyLabel: String {
        switch self {
        case .gemini: return "Google API Key"
        case .openRouter: return "OpenRouter API Key"
        case .groq: return "Groq API Key"
        }
    }

    /// Where the person gets a key (shown as plain text, never opened by the app).
    var keyHost: String {
        switch self {
        case .gemini: return "aistudio.google.com"
        case .openRouter: return "openrouter.ai/keys"
        case .groq: return "console.groq.com/keys"
        }
    }

    /// Keychain slots. Gemini keeps the original names, so an existing install's keys are still found.
    var keychainAccount: String {
        switch self {
        case .gemini: return "api-key"
        case .openRouter: return "api-key-openrouter"
        case .groq: return "api-key-groq"
        }
    }

    var backupKeychainAccount: String {
        switch self {
        case .gemini: return "api-key-fallback"
        case .openRouter: return "api-key-openrouter-fallback"
        case .groq: return "api-key-groq-fallback"
        }
    }

    /// Only Gemini can synthesize speech (pronunciation).
    var supportsSpeech: Bool { self == .gemini }

    /// The model list is cached in its own file per provider (Gemini keeps the original name).
    var catalogueFileName: String {
        switch self {
        case .gemini: return "ModelCatalogue.json"
        case .openRouter: return "ModelCatalogue-openrouter.json"
        case .groq: return "ModelCatalogue-groq.json"
        }
    }

    /// UserDefaults key of the chosen model (Gemini keeps the original key).
    var selectedModelKey: String {
        switch self {
        case .gemini: return "selectedModelID"
        case .openRouter: return "selectedModelID.openrouter"
        case .groq: return "selectedModelID.groq"
        }
    }

    /// Where a provider's requests go. Both are OpenAI-compatible; Gemini has its own client.
    var openAIBaseURL: URL? {
        switch self {
        case .gemini: return nil
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")
        case .groq: return URL(string: "https://api.groq.com/openai/v1")
        }
    }
}

extension AIModel {
    /// A model without a provider is a Gemini one (every model saved before providers existed).
    var resolvedProvider: AIProvider { provider ?? .gemini }
}
