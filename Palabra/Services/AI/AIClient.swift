import Foundation

/// Everything the app needs from a Google AI backend. `GeminiClient` is the
/// real implementation; `StubAIClient` backs previews and UI tests.
protocol AIClient: Sendable {
    func listModels(apiKey: String) async -> Result<[AIModel], AIError>
    func generateWord(_ input: String, apiKey: String, model: AIModel) async -> Result<WordContent, AIError>
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String) async -> Result<String, AIError>
}
