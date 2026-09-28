import Foundation
@testable import Palabra

/// Controllable `AIClient` for tests that don't exercise real networking.
final class MockAIClient: AIClient, @unchecked Sendable {
    var listModelsResult: Result<[AIModel], AIError> = .success([])
    var generateWordResult: Result<WordContent, AIError> = .failure(.malformedResponse)
    var sendChatResult: Result<String, AIError> = .failure(.malformedResponse)
    var synthesizeSpeechResult: Result<Data, AIError> = .failure(.malformedResponse)

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> { listModelsResult }
    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> { generateWordResult }
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> { sendChatResult }
    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> { synthesizeSpeechResult }
}
