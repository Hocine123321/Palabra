import Foundation
import Observation

/// What the AI thought of a written answer.
struct ExamAIGrade: Equatable, Sendable {
    /// 0...1.
    var score: Double
    /// The sentence written correctly, when the answer had mistakes.
    var corrected: String?
    var feedback: String
}

/// Checks a free-written answer. The live one asks the AI; tests use a double.
@MainActor
protocol ExamGrading {
    func grade(question: ExamQuestion, answer: String) async -> Result<ExamAIGrade, AIError>
}

/// One run through an exam: shows a question, takes the answer, grades it, moves on. All the rules about scores live
/// here and in `AnswerMatcher`; the views only show the state.
@MainActor
@Observable
final class ExamSession {
    enum Phase: Equatable {
        case asking
        /// The answer is in; the question shows the result until "Next".
        case answered
        case finished
    }

    let config: ExamConfig
    private(set) var questions: [ExamQuestion]
    private(set) var index = 0
    private(set) var records: [ExamAnswerRecord] = []
    private(set) var phase: Phase
    /// The last answer's result, while `phase == .answered`.
    private(set) var lastRecord: ExamAnswerRecord?
    /// How a typed or spoken answer was judged (for "mind the accents" and similar notes).
    private(set) var lastTypedKind: AnswerMatcher.Grade.Kind?
    private(set) var isGrading = false
    /// The AI could not check a written answer: the person says how it went.
    private(set) var needsSelfCheck = false
    /// The answer waiting for a self-check.
    private(set) var pendingWritten: String?

    private let grader: ExamGrading?
    private let now: () -> Date
    private let startedAt: Date
    private var finishedDuration: TimeInterval?
    @ObservationIgnored private var onFinished: (([ExamAnswerRecord], TimeInterval) -> Void)?

    init(
        questions: [ExamQuestion], config: ExamConfig, grader: ExamGrading? = nil,
        now: @escaping () -> Date = Date.init, onFinished: (([ExamAnswerRecord], TimeInterval) -> Void)? = nil
    ) {
        self.questions = questions
        self.config = config
        self.grader = grader
        self.now = now
        self.onFinished = onFinished
        startedAt = now()
        phase = questions.isEmpty ? .finished : .asking
    }

    // MARK: - State

    var current: ExamQuestion? { phase == .finished || !questions.indices.contains(index) ? nil : questions[index] }
    var total: Int { questions.count }
    var answeredCount: Int { records.count }
    /// 0...1 through the exam.
    var progress: Double { total == 0 ? 1 : Double(records.count) / Double(total) }
    var scoreSum: Double { records.reduce(0) { $0 + $1.score } }
    /// 0...1.
    var fraction: Double { records.isEmpty ? 0 : scoreSum / Double(records.count) }
    var percent: Int { Int((fraction * 100).rounded()) }
    var correctCount: Int { records.filter(\.isCorrect).count }
    var duration: TimeInterval { finishedDuration ?? now().timeIntervalSince(startedAt) }
    /// The questions that were not fully right, to go over again.
    var missedQuestions: [ExamQuestion] {
        let missed = Set(records.filter { !$0.isCorrect }.map(\.id))
        return questions.filter { missed.contains($0.id) }
    }

    /// Average score per skill, for the result screen.
    func scoreBySkill() -> [(skill: ExamSkill, fraction: Double, count: Int)] {
        ExamScoring.bySkill(records)
    }

    // MARK: - Answers

    func answerChoice(_ option: Int) {
        guard phase == .asking, let question = current, case .choice(let options, let correct) = question.format, options.indices.contains(option) else { return }
        record(question, score: option == correct ? 1 : 0, given: options[option])
    }

    func answerTyped(_ text: String) {
        guard phase == .asking, let question = current, case .typed(let accepted, let english) = question.format else { return }
        let grade = AnswerMatcher.grade(typed: text, accepted: accepted, english: english)
        lastTypedKind = grade.kind
        record(question, score: grade.score, given: text)
    }

    func answerOrder(_ tokens: [String]) {
        guard phase == .asking, let question = current, case .reorder(_, let answer) = question.format else { return }
        record(question, score: AnswerMatcher.orderScore(given: tokens, answer: answer), given: tokens.joined(separator: " "))
    }

    /// `mistakes` = wrong pairings made before every pair was matched.
    func answerMatch(mistakes: Int) {
        guard phase == .asking, let question = current, case .match(let pairs) = question.format else { return }
        let score = max(0, 1 - Double(max(0, mistakes)) / Double(max(1, pairs.count)))
        record(question, score: score, given: "\(mistakes)")
    }

    /// What the recognizer heard, or an empty text when it heard nothing.
    func answerSpoken(_ heard: String) {
        guard phase == .asking, let question = current, case .spoken(let target) = question.format else { return }
        let grade = AnswerMatcher.grade(typed: heard, accepted: [target])
        lastTypedKind = grade.kind
        record(question, score: grade.score, given: heard)
    }

    /// A written answer: checked by the AI, or by the person when the AI can't be reached.
    func answerWritten(_ text: String) async {
        guard phase == .asking, let question = current, case .written = question.format else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        guard let grader else {
            pendingWritten = answer
            needsSelfCheck = true
            return
        }
        isGrading = true
        needsSelfCheck = false
        let outcome = await grader.grade(question: question, answer: answer)
        isGrading = false
        // The person moved on or left while the AI was thinking.
        guard phase == .asking, current?.id == question.id else { return }
        switch outcome {
        case .success(let grade):
            let score = grade.score.isFinite ? min(max(grade.score, 0), 1) : 0
            let expected = grade.corrected ?? question.expectedText
            record(question, score: score, given: answer, expected: expected, feedback: grade.feedback)
        case .failure:
            pendingWritten = answer
            needsSelfCheck = true
        }
    }

    /// "How did you do?" when nothing could check the answer.
    func selfGrade(_ score: Double) {
        guard phase == .asking, let question = current, needsSelfCheck else { return }
        record(question, score: min(max(score, 0), 1), given: pendingWritten ?? "")
    }

    /// "I don't know": no points, and the answer is shown.
    func giveUp() {
        guard phase == .asking, let question = current else { return }
        lastTypedKind = .wrong
        record(question, score: 0, given: "")
    }

    /// Takes the question out of the exam without a score (it cannot be answered right now, for example speaking).
    func skipWithoutScore() {
        guard phase == .asking, let question = current else { return }
        questions.removeAll { $0.id == question.id }
        needsSelfCheck = false
        pendingWritten = nil
        if index >= questions.count { finish() }
    }

    /// Ends the exam here: what was answered so far is the result.
    func endEarly() {
        guard phase != .finished else { return }
        finish()
    }

    func next() {
        guard phase == .answered else { return }
        lastRecord = nil
        lastTypedKind = nil
        needsSelfCheck = false
        pendingWritten = nil
        index += 1
        if index >= questions.count { finish() } else { phase = .asking }
    }

    // MARK: - Internals

    private func record(_ question: ExamQuestion, score: Double, given: String, expected: String? = nil, feedback: String? = nil) {
        let result = ExamAnswerRecord(
            id: question.id, wordID: question.wordID,
            involvedWordIDs: question.involvedWordIDs.count > 1 ? question.involvedWordIDs : nil,
            headword: question.headword, kindRaw: question.kind.rawValue, score: score,
            given: given, expected: expected ?? question.expectedText, feedback: feedback
        )
        records.append(result)
        lastRecord = result
        needsSelfCheck = false
        pendingWritten = nil
        phase = .answered
    }

    private func finish() {
        guard phase != .finished || finishedDuration == nil else { return }
        finishedDuration = now().timeIntervalSince(startedAt)
        phase = .finished
        let callback = onFinished
        onFinished = nil
        callback?(records, finishedDuration ?? 0)
    }
}

/// Scores of a set of answers, shared by a live exam and a saved one.
enum ExamScoring {
    static func bySkill(_ records: [ExamAnswerRecord]) -> [(skill: ExamSkill, fraction: Double, count: Int)] {
        var sums: [ExamSkill: (Double, Int)] = [:]
        for record in records {
            guard let skill = record.kind?.skill else { continue }
            let old = sums[skill] ?? (0, 0)
            sums[skill] = (old.0 + record.score, old.1 + 1)
        }
        return ExamSkill.allCases.compactMap { skill in
            guard let value = sums[skill], value.1 > 0 else { return nil }
            return (skill, value.0 / Double(value.1), value.1)
        }
    }

    static func percent(_ records: [ExamAnswerRecord]) -> Int {
        records.isEmpty ? 0 : Int((records.reduce(0) { $0 + $1.score } / Double(records.count) * 100).rounded())
    }
}
