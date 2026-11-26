import Foundation

/// Which provider a model-list request is for. `RoutingAIClient.listModels` has no model to go by, so the catalogue that asks
/// says (task-local: it follows the request through the resilience wrapper without changing any signature).
enum AIProviderContext {
    @TaskLocal static var listing: AIProvider?
}

/// One `AIClient` for every provider: each request goes to the client of its model's provider (a model saved before
/// providers existed has none, which means Gemini). Everything above it (retries, backup keys, every screen) is unchanged.
final class RoutingAIClient: AIClient, RetryHintProviding, @unchecked Sendable {
    private let clients: [AIProvider: AIClient]
    private let lock = NSLock()
    private var listingDefault: AIProvider

    init(gemini: AIClient, openRouter: AIClient, groq: AIClient, active: AIProvider = .gemini) {
        clients = [.gemini: gemini, .openRouter: openRouter, .groq: groq]
        listingDefault = active
    }

    convenience init(session: URLSession = .shared, active: AIProvider = .gemini) {
        self.init(
            gemini: GeminiClient(session: session),
            openRouter: OpenAICompatibleClient(provider: .openRouter, session: session),
            groq: OpenAICompatibleClient(provider: .groq, session: session),
            active: active
        )
    }

    /// The provider a model-list request is for when the caller does not say (the active one).
    var activeProvider: AIProvider {
        get { lock.lock(); defer { lock.unlock() }; return listingDefault }
        set { lock.lock(); listingDefault = newValue; lock.unlock() }
    }

    private func client(for model: AIModel) -> AIClient { clients[model.resolvedProvider] ?? clients[.gemini]! }

    func takeRetryHint() -> TimeInterval? {
        for client in clients.values {
            if let hint = (client as? RetryHintProviding)?.takeRetryHint() { return hint }
        }
        return nil
    }

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        let provider = AIProviderContext.listing ?? activeProvider
        return await (clients[provider] ?? clients[.gemini]!).listModels(apiKey: apiKey)
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        await client(for: model).generateWord(input, apiKey: apiKey, model: model, language: language)
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        await client(for: model).sendChat(apiKey: apiKey, model: model, word: word, history: history, newMessage: newMessage, language: language)
    }

    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> {
        await client(for: model).synthesizeSpeech(text, apiKey: apiKey, model: model)
    }

    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        await client(for: model).generateJSON(prompt: prompt, systemInstruction: systemInstruction, schema: schema, apiKey: apiKey, model: model, temperature: temperature)
    }

    func generateJSON(prompt: String, image: AIImage, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        await client(for: model).generateJSON(prompt: prompt, image: image, systemInstruction: systemInstruction, schema: schema, apiKey: apiKey, model: model, temperature: temperature)
    }

    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> {
        await client(for: model).organizeWords(words, existingCategories: existingCategories, settings: settings, apiKey: apiKey, model: model, language: language)
    }
}
