import Foundation

/// Deterministic `AIClient` for SwiftUI previews and UI tests (`-UITestStub`).
/// Sends "fallo" as the word or a chat message to exercise the failure path.
final class StubAIClient: AIClient {
    static let sampleModels: [AIModel] = [
        AIModel(id: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "Fast and cost-efficient.", inputTokenLimit: 1_000_000, outputTokenLimit: 8192),
        AIModel(id: "models/gemini-2.5-pro", displayName: "Gemini 2.5 Pro", description: "Most capable.", inputTokenLimit: 2_000_000, outputTokenLimit: 8192)
    ]

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .failure(.invalidAPIKey) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .success(Self.sampleModels)
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel) async -> Result<WordContent, AIError> {
        try? await Task.sleep(nanoseconds: 400_000_000)
        if input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(Self.sampleContent(for: input))
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String) async -> Result<String, AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if newMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success("Think of \"\(word.word)\" this way: \(newMessage)")
    }

    static func sampleContent(for input: String) -> WordContent {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = word.isEmpty ? "palabra" : word
        return WordContent(
            word: display,
            examples: [
                .init(context: "At school", spanish: "Usamos \"\(display)\" en clase todos los días.", english: "We use \"\(display)\" in class every day."),
                .init(context: "With friends", spanish: "Mi amigo dijo \"\(display)\" ayer.", english: "My friend said \"\(display)\" yesterday."),
                .init(context: "At home", spanish: "Mi familia usa \"\(display)\" en casa.", english: "My family uses \"\(display)\" at home.")
            ],
            meaning: .init(translations: ["(sample translation)"], explanation: "Placeholder content from the stub AI client, used for previews and UI tests."),
            usage: .init(explanation: "Sample usage explanation.", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "noun", groups: [.init(label: "Singular / Plural", items: [.init(form: display, note: nil)])]),
            similarWords: [.init(word: "ejemplo", difference: "A generic related word shown for previews.")]
        )
    }
}
