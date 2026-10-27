import Foundation

/// Fresh material AI wrote for one word: a new fill-in-the-blank sentence and an English sentence to translate.
struct ExamAIItem: Equatable, Sendable {
    let wordID: UUID
    var cloze: String?
    var clozeAnswer: String?
    var clozeEnglish: String?
    var translatePrompt: String?
    var reference: String?
}
