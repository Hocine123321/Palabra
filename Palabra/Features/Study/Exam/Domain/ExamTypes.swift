import Foundation

/// One library word, as the exam sees it: plain values, so Study never imports `Word`.
/// `AppEnvironment.examWords()` builds these (it is the one place that knows both sides).
struct ExamWord: Identifiable, Equatable, Sendable {
    struct Example: Equatable, Sendable {
        let spanish: String
        let english: String
    }

    struct Form: Equatable, Sendable {
        let label: String
        let form: String
        let note: String?
    }

    struct Similar: Equatable, Sendable {
        let word: String
        let difference: String
    }

    let id: UUID
    let headword: String
    let translations: [String]
    let partOfSpeech: String
    let examples: [Example]
    let forms: [Form]
    let similar: [Similar]
    let category: String?
    let tags: [String]
    let createdAt: Date
    /// The word is on the Need Review list.
    let needsReview: Bool

    var primaryTranslation: String { translations.first ?? "" }
}

/// What a question practices. The setup screen offers these, not the individual question kinds.
enum ExamSkill: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case vocabulary, typing, grammar, listening, speaking, writing

    var id: String { rawValue }

    /// A localization key.
    var title: String {
        switch self {
        case .vocabulary: return "Meaning"
        case .typing: return "Typing"
        case .grammar: return "Grammar"
        case .listening: return "Listening"
        case .speaking: return "Speaking"
        case .writing: return "Writing"
        }
    }

    /// A localization key.
    var detail: String {
        switch self {
        case .vocabulary: return "Choose what a word means, in both directions."
        case .typing: return "Type the word or its meaning."
        case .grammar: return "Fill in blanks, pick the right form, put words in order."
        case .listening: return "Hear a word and type it."
        case .speaking: return "Say a word out loud."
        case .writing: return "Write your own sentences. Needs AI to check them."
        }
    }

    var systemImage: String {
        switch self {
        case .vocabulary: return "character.book.closed"
        case .typing: return "keyboard"
        case .grammar: return "text.word.spacing"
        case .listening: return "ear"
        case .speaking: return "mic"
        case .writing: return "pencil.and.scribble"
        }
    }

    var needsAI: Bool { self == .writing }

    var kinds: [ExamQuestionKind] {
        switch self {
        case .vocabulary: return [.meaningChoice, .reverseChoice, .similarChoice, .matchPairs]
        case .typing: return [.typeSpanish, .typeMeaning]
        case .grammar: return [.fillBlank, .formChoice, .reorder]
        case .listening: return [.listening]
        case .speaking: return [.speaking]
        case .writing: return [.writeSentence, .translate]
        }
    }
}

enum ExamQuestionKind: String, CaseIterable, Codable, Hashable, Sendable {
    case meaningChoice, reverseChoice, similarChoice, matchPairs
    case typeSpanish, typeMeaning
    case fillBlank, formChoice, reorder
    case listening, speaking
    case writeSentence, translate

    var skill: ExamSkill {
        switch self {
        case .meaningChoice, .reverseChoice, .similarChoice, .matchPairs: return .vocabulary
        case .typeSpanish, .typeMeaning: return .typing
        case .fillBlank, .formChoice, .reorder: return .grammar
        case .listening: return .listening
        case .speaking: return .speaking
        case .writeSentence, .translate: return .writing
        }
    }

    /// A localization key: the line above the question.
    var instruction: String {
        switch self {
        case .meaningChoice: return "What does this mean?"
        case .reverseChoice: return "Which Spanish word is this?"
        case .similarChoice: return "Which word is closest in meaning?"
        case .matchPairs: return "Match each word with its meaning."
        case .typeSpanish: return "Type this in Spanish."
        case .typeMeaning: return "Type what this means."
        case .fillBlank: return "Fill in the blank."
        case .formChoice: return "Choose the right form."
        case .reorder: return "Put the words in order."
        case .listening: return "Type what you hear."
        case .speaking: return "Say this in Spanish."
        case .writeSentence: return "Write a Spanish sentence with this word."
        case .translate: return "Translate this into Spanish."
        }
    }
}

/// Where the exam's words come from.
enum ExamSource: Hashable, Codable, Sendable {
    case all
    /// The words you get wrong most, and the ones you have not been tested on yet.
    case weakest
    /// The most recently added words.
    case recent
    case needReview
    case section(String)
    case tag(String)
    /// Exactly these words (practicing the ones just missed).
    case words([UUID])
}

struct ExamConfig: Hashable, Codable, Sendable {
    static let questionCounts = [5, 10, 20, 30]

    var source: ExamSource = .all
    var questionCount = 10
    var skills: Set<ExamSkill> = [.vocabulary, .typing, .grammar]
    /// Lets AI write fresh sentences and check written answers. Off = nothing in the exam needs a connection.
    var useAI = false

    /// The question kinds the chosen skills allow (the writing ones only with AI).
    var kinds: [ExamQuestionKind] {
        ExamSkill.allCases
            .filter { skills.contains($0) && (useAI || !$0.needsAI) }
            .flatMap(\.kinds)
    }
}

/// Stored (inside `ExamResult` and the backup), so decoding is tolerant: a field an older version did not write falls back
/// to its default. New fields must be optional or given a default here.
extension ExamConfig {
    private enum CodingKeys: String, CodingKey { case source, questionCount, skills, useAI }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        source = try c.decodeIfPresent(ExamSource.self, forKey: .source) ?? .all
        questionCount = try c.decodeIfPresent(Int.self, forKey: .questionCount) ?? 10
        skills = try c.decodeIfPresent(Set<ExamSkill>.self, forKey: .skills) ?? [.vocabulary, .typing, .grammar]
        useAI = try c.decodeIfPresent(Bool.self, forKey: .useAI) ?? false
    }
}

/// One question. `subject` is shown big (a word, a sentence); `hint` under it; both are content, shown verbatim.
struct ExamQuestion: Identifiable, Equatable, Sendable {
    struct Pair: Equatable, Sendable {
        let wordID: UUID
        let left: String
        let right: String
    }

    enum Format: Equatable, Sendable {
        case choice(options: [String], correct: Int)
        /// Any of `accepted` is right. `english` = the answer is in English (articles and "to" are optional).
        case typed(accepted: [String], english: Bool)
        /// `tokens` are shuffled; `answer` is the right order.
        case reorder(tokens: [String], answer: [String])
        case match(pairs: [Pair])
        case spoken(target: String)
        /// Free writing, checked by AI. `reference` is a model answer (shown afterwards).
        case written(reference: String?)
    }

    let id: UUID
    let kind: ExamQuestionKind
    let wordID: UUID
    let headword: String
    let subject: String
    let hint: String?
    let format: Format
    /// Shown after answering (the translation of a sentence, how similar words differ, ...).
    let explanation: String?
    /// Words a result counts for (a matching question covers several).
    let involvedWordIDs: [UUID]
    /// Spanish text the phone reads aloud for this question (listening).
    let speakText: String?

    init(
        id: UUID = UUID(), kind: ExamQuestionKind, wordID: UUID, headword: String, subject: String,
        hint: String? = nil, format: Format, explanation: String? = nil, involvedWordIDs: [UUID]? = nil, speakText: String? = nil
    ) {
        self.speakText = speakText
        self.id = id
        self.kind = kind
        self.wordID = wordID
        self.headword = headword
        self.subject = subject
        self.hint = hint
        self.format = format
        self.explanation = explanation
        self.involvedWordIDs = involvedWordIDs ?? [wordID]
    }

    /// The best answer, as text.
    var expectedText: String {
        switch format {
        case .choice(let options, let correct): return options.indices.contains(correct) ? options[correct] : ""
        case .typed(let accepted, _): return accepted.first ?? ""
        case .reorder(_, let answer): return answer.joined(separator: " ")
        case .match(let pairs): return pairs.map { "\($0.left) = \($0.right)" }.joined(separator: "\n")
        case .spoken(let target): return target
        case .written(let reference): return reference ?? ""
        }
    }
}

/// What happened on one question. Stored (JSON) with the exam, so: tolerant decoding, new fields optional.
struct ExamAnswerRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var wordID: UUID
    var involvedWordIDs: [UUID]?
    var headword: String
    var kindRaw: String
    /// 0...1. Partial credit: a missing accent, one typo, some matching pairs right.
    var score: Double
    var given: String
    var expected: String
    var feedback: String?

    var kind: ExamQuestionKind? { ExamQuestionKind(rawValue: kindRaw) }
    var words: [UUID] { involvedWordIDs ?? [wordID] }
    var isCorrect: Bool { score >= 0.99 }
    var isPartial: Bool { score >= 0.3 && score < 0.99 }
}

/// How one word has gone in recent exams.
struct ExamWordStat: Equatable, Sendable {
    var attempts = 0
    var scoreSum = 0.0
    var lastSeen = Date.distantPast

    var accuracy: Double { attempts == 0 ? 0 : scoreSum / Double(attempts) }
}
