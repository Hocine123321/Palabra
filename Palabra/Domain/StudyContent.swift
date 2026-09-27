import Foundation

/// One AI-generated flashcard suggestion, before the learner reviews and
/// saves it. Distinct from `Flashcard` (Services/Storage), which additionally
/// carries the spaced-repetition state and a stable identity.
struct FlashcardDraft: Codable, Equatable, Sendable {
    var front: String
    var back: String
    var hint: String?
}

/// One AI-generated multiple-choice quiz question, kept in memory only for a
/// single quiz-taking session (not persisted).
struct QuizQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var question: String
    var options: [String]
    var correctIndex: Int
    var explanation: String?

    private enum CodingKeys: String, CodingKey {
        case question, options, correctIndex, explanation
    }

    init(question: String, options: [String], correctIndex: Int, explanation: String? = nil) {
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        question = try container.decode(String.self, forKey: .question)
        options = try container.decode([String].self, forKey: .options)
        correctIndex = try container.decode(Int.self, forKey: .correctIndex)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(question, forKey: .question)
        try container.encode(options, forKey: .options)
        try container.encode(correctIndex, forKey: .correctIndex)
        try container.encodeIfPresent(explanation, forKey: .explanation)
    }
}
