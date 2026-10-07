import Foundation
@testable import Palabra

/// Controllable `AIClient` for tests that don't exercise real networking.
final class MockAIClient: AIClient, @unchecked Sendable {
    var listModelsResult: Result<[AIModel], AIError> = .success([])
    var generateWordResult: Result<WordContent, AIError> = .failure(.malformedResponse)
    /// When non-empty, `generateWord` consumes these in order (one per call)
    /// before falling back to `generateWordResult` once exhausted — for
    /// tests that need a call to behave differently each time (e.g. the
    /// queue processor retrying a word).
    var generateWordScript: [Result<WordContent, AIError>] = []
    private(set) var generateWordCallCount = 0
    var sendChatResult: Result<String, AIError> = .failure(.malformedResponse)
    var synthesizeSpeechResult: Result<Data, AIError> = .failure(.malformedResponse)
    var generateJSONResult: Result<String, AIError> = .success("{}")
    var organizeWordsResult: Result<OrganizerBatchResult, AIError> = .success(OrganizerBatchResult(entries: []))
    private(set) var organizeCalls: [(words: [OrganizerWordInput], existing: [String])] = []

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> { listModelsResult }
    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        generateWordCallCount += 1
        if !generateWordScript.isEmpty { return generateWordScript.removeFirst() }
        return generateWordResult
    }
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> { sendChatResult }
    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> { synthesizeSpeechResult }
    /// Every `generateJSON` call, in order — lets tests assert what was actually sent.
    private(set) var generateJSONCalls: [(prompt: String, systemInstruction: String, schema: [String: Any]?)] = []
    /// When non-empty, `generateJSON` consumes these in order before falling back to `generateJSONResult`.
    var generateJSONScript: [Result<String, AIError>] = []
    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        generateJSONCalls.append((prompt, systemInstruction, schema))
        if !generateJSONScript.isEmpty { return generateJSONScript.removeFirst() }
        return generateJSONResult
    }
    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> {
        organizeCalls.append((words, existingCategories))
        return organizeWordsResult
    }
}
