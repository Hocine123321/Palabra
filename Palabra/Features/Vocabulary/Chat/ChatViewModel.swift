import Foundation
import Observation

/// Drives the per-word chat: sends the trimmed draft with the prior history,
/// appends a `.failed` placeholder (with a human message) on error, and
/// persists the thread through the repository after every change.
@MainActor
@Observable
final class ChatViewModel {
    enum SendState: Equatable { case idle, sending }

    private(set) var messages: [ChatMessage]
    var draft: String = ""
    private(set) var sendState: SendState = .idle

    private let wordID: UUID
    private let word: WordContent
    private let environment: AppEnvironment

    init(word: Word, environment: AppEnvironment) {
        wordID = word.id
        self.word = word.content
        messages = word.chat
        self.environment = environment
    }

    func send(_ text: String? = nil) async {
        let trimmed = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sendState == .idle else { return }
        draft = ""
        let priorHistory = messages
        messages.append(ChatMessage(role: .user, text: trimmed))
        persist()
        await requestReply(history: priorHistory, newMessage: trimmed)
    }

    func retryLastFailed() async {
        guard let last = messages.last, last.status == .failed else { return }
        messages.removeLast()
        guard let retryMessage = messages.last, retryMessage.role == .user else { return }
        let history = Array(messages.dropLast())
        persist()
        await requestReply(history: history, newMessage: retryMessage.text)
    }

    func clear() {
        messages = []
        persist()
    }

    private func requestReply(history: [ChatMessage], newMessage: String) async {
        sendState = .sending
        defer { sendState = .idle }
        guard environment.hasAPIKey, let apiKey = environment.apiKey, let model = environment.selectedModel else {
            appendFailure(environment.hasAPIKey ? .noModelSelected : .missingAPIKey)
            persist()
            return
        }
        switch await environment.ai.sendChat(apiKey: apiKey, model: model, word: word, history: history, newMessage: newMessage, language: environment.aiLanguage) {
        case .success(let text):
            messages.append(ChatMessage(role: .assistant, text: text))
        case .failure(let error):
            appendFailure(error)
            // The failed message keeps a Retry button; fix the selection so that retry works.
            if case .modelUnavailable = error { await environment.repairMissingModel() }
        }
        persist()
    }

    private func appendFailure(_ error: AIError) {
        messages.append(ChatMessage(role: .assistant, text: "", status: .failed, errorText: error.userMessage))
    }

    private func persist() {
        environment.repository.updateChat(id: wordID, messages: messages)
    }
}
