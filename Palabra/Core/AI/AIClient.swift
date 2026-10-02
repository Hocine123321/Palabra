import Foundation

/// Everything the app needs from a Google AI backend.
protocol AIClient: Sendable {
    func listModels(apiKey: String) async -> Result<[AIModel], AIError>
    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError>
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError>
    /// Synthesizes spoken audio for `text` (always the Spanish headword —
    /// Gemini TTS detects the language from the text itself, so this takes
    /// no `SupportedLanguage`, unlike the explanation-generating methods
    /// above). Returns a complete, playable WAV file.
    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError>
    /// Generic structured call for study tools: sends `prompt` under
    /// `systemInstruction`, optionally constrained by a Gemini `responseSchema`,
    /// and returns the raw JSON text. Callers decode and validate it themselves.
    /// New tools should build on this instead of adding feature-specific methods.
    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError>
    /// Places a batch of saved words into sections and tags them.
    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError>
}

/// Optional: a client that can tell how long the server asked us to wait after a rate limit.
protocol RetryHintProviding: Sendable {
    /// Seconds Google asked us to wait after the most recent rate-limit response, if any.
    func takeRetryHint() -> TimeInterval?
}

extension AIClient {
    func generateWord(_ input: String, apiKey: String, model: AIModel) async -> Result<WordContent, AIError> {
        await generateWord(input, apiKey: apiKey, model: model, language: .english)
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String) async -> Result<String, AIError> {
        await sendChat(apiKey: apiKey, model: model, word: word, history: history, newMessage: newMessage, language: .english)
    }
}
