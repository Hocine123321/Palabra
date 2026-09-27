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

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        try? await Task.sleep(nanoseconds: 400_000_000)
        if input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(Self.sampleContent(for: input, language: language))
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if newMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(language == .arabic ? "فكّر في \"\(word.word)\" بهذه الطريقة: \(newMessage)" : "Think of \"\(word.word)\" this way: \(newMessage)")
    }

    func generateFlashcards(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[FlashcardDraft], AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success([
            FlashcardDraft(front: "Sample question about \(subject.isEmpty ? "your notes" : subject)", back: "Sample answer drawn from the pasted notes.", hint: nil),
            FlashcardDraft(front: "Second sample question", back: "Second sample answer.", hint: "A short hint")
        ])
    }

    func generateQuiz(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[QuizQuestion], AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success([
            QuizQuestion(question: "Sample question about \(subject.isEmpty ? "your notes" : subject)?", options: ["Correct option", "Wrong option A", "Wrong option B", "Wrong option C"], correctIndex: 0, explanation: "Placeholder explanation from the stub AI client.")
        ])
    }

    static func sampleContent(for input: String, language: SupportedLanguage = .english) -> WordContent {
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
            similarWords: [.init(word: "ejemplo", difference: "A generic related word shown for previews.")],
            contentLanguage: language
        )
    }
}
