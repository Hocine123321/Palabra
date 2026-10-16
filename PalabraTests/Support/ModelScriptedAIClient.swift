import Foundation
@testable import Palabra

/// An `AIClient` whose answers depend on the model asked: lets tests prove which model served which request.
final class ModelScriptedAIClient: AIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(model: String, key: String)] = []
    /// What each model answers (by model id). Models not listed answer "ok".
    var results: [String: Result<String, AIError>] = [:]
    /// Keys that always fail, whatever the model.
    var failingKeys: [String: AIError] = [:]
    var speechResult: Result<Data, AIError> = .success(Data([1]))

    var models: [String] { lock.lock(); defer { lock.unlock() }; return calls.map(\.model) }
    var keys: [String] { lock.lock(); defer { lock.unlock() }; return calls.map(\.key) }

    private func record(_ model: AIModel, _ key: String) -> Result<String, AIError> {
        lock.lock(); defer { lock.unlock() }
        calls.append((model.id, key))
        if let error = failingKeys[key] { return .failure(error) }
        return results[model.id] ?? .success("ok")
    }

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> { .success([]) }
    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> { .failure(.malformedResponse) }
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        record(model, apiKey)
    }
    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> {
        if case .failure(let error) = record(model, apiKey) { return .failure(error) }
        return speechResult
    }
    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        record(model, apiKey)
    }
    func generateJSON(prompt: String, image: AIImage, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        record(model, apiKey)
    }
    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> { .failure(.malformedResponse) }
}
