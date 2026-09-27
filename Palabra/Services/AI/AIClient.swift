import Foundation

/// Everything the app needs from a Google AI backend.
protocol AIClient: Sendable {
    func listModels(apiKey: String) async -> Result<[AIModel], AIError>
    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError>
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError>

    /// Turns pasted class notes (any subject) into draft flashcards for the
    /// learner to review before saving.
    func generateFlashcards(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[FlashcardDraft], AIError>

    /// Turns pasted class notes (any subject) into a short multiple-choice
    /// quiz for immediate self-testing.
    func generateQuiz(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[QuizQuestion], AIError>
}

extension AIClient {
    func generateWord(_ input: String, apiKey: String, model: AIModel) async -> Result<WordContent, AIError> {
        await generateWord(input, apiKey: apiKey, model: model, language: .english)
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String) async -> Result<String, AIError> {
        await sendChat(apiKey: apiKey, model: model, word: word, history: history, newMessage: newMessage, language: .english)
    }

    func generateFlashcards(from notes: String, subject: String, apiKey: String, model: AIModel) async -> Result<[FlashcardDraft], AIError> {
        await generateFlashcards(from: notes, subject: subject, apiKey: apiKey, model: model, language: .english)
    }

    func generateQuiz(from notes: String, subject: String, apiKey: String, model: AIModel) async -> Result<[QuizQuestion], AIError> {
        await generateQuiz(from: notes, subject: subject, apiKey: apiKey, model: model, language: .english)
    }
}
