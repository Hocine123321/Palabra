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
}

extension AIClient {
    func generateWord(_ input: String, apiKey: String, model: AIModel) async -> Result<WordContent, AIError> {
        await generateWord(input, apiKey: apiKey, model: model, language: .english)
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String) async -> Result<String, AIError> {
        await sendChat(apiKey: apiKey, model: model, word: word, history: history, newMessage: newMessage, language: .english)
    }
}
