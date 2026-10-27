import XCTest
@testable import Palabra

@MainActor
private final class StubGrader: ExamGrading {
    var result: Result<ExamAIGrade, AIError>
    private(set) var graded: [(question: ExamQuestion, answer: String)] = []

    init(_ result: Result<ExamAIGrade, AIError>) { self.result = result }

    func grade(question: ExamQuestion, answer: String) async -> Result<ExamAIGrade, AIError> {
        graded.append((question, answer))
        return result
    }
}

@MainActor
final class ExamSessionTests: XCTestCase {
    private let word = UUID()

    private func choice(correct: Int = 1) -> ExamQuestion {
        ExamQuestion(kind: .meaningChoice, wordID: word, headword: "hablar", subject: "hablar",
                     format: .choice(options: ["to eat", "to speak", "to run"], correct: correct))
    }

    private func typed(_ accepted: String = "está") -> ExamQuestion {
        ExamQuestion(kind: .typeSpanish, wordID: word, headword: "estar", subject: "to be",
                     format: .typed(accepted: [accepted], english: false))
    }

    private func reorder() -> ExamQuestion {
        ExamQuestion(kind: .reorder, wordID: word, headword: "hablar", subject: "I speak Spanish.",
                     format: .reorder(tokens: ["Spanish", "Hablo"], answer: ["Hablo", "Spanish"]))
    }

    private func match(pairs: Int = 4) -> ExamQuestion {
        let items = (0..<pairs).map { ExamQuestion.Pair(wordID: UUID(), left: "w\($0)", right: "m\($0)") }
        return ExamQuestion(kind: .matchPairs, wordID: items[0].wordID, headword: "w0", subject: "",
                            format: .match(pairs: items), involvedWordIDs: items.map(\.wordID))
    }

    private func written() -> ExamQuestion {
        ExamQuestion(kind: .writeSentence, wordID: word, headword: "hablar", subject: "hablar", format: .written(reference: "Hablo mucho."))
    }

    private func session(_ questions: [ExamQuestion], grader: ExamGrading? = nil, onFinished: (([ExamAnswerRecord], TimeInterval) -> Void)? = nil) -> ExamSession {
        ExamSession(questions: questions, config: ExamConfig(), grader: grader, onFinished: onFinished)
    }

    func testARightChoiceScoresOneAndWaitsForNext() throws {
        let exam = session([choice(), typed()])
        exam.answerChoice(1)
        XCTAssertEqual(exam.phase, .answered)
        XCTAssertEqual(exam.lastRecord?.score, 1)
        XCTAssertEqual(exam.lastRecord?.given, "to speak")
        exam.next()
        XCTAssertEqual(exam.phase, .asking)
        XCTAssertEqual(exam.current?.kind, .typeSpanish)
    }

    func testAWrongChoiceScoresZeroAndRecordsTheRightAnswer() {
        let exam = session([choice()])
        exam.answerChoice(0)
        XCTAssertEqual(exam.lastRecord?.score, 0)
        XCTAssertEqual(exam.lastRecord?.expected, "to speak")
    }

    func testASecondTapOnTheSameQuestionIsIgnored() {
        let exam = session([choice(), typed()])
        exam.answerChoice(1)
        exam.answerChoice(0)
        XCTAssertEqual(exam.records.count, 1)
        XCTAssertEqual(exam.records[0].score, 1)
    }

    func testTypingGivesPartialCreditForAMissingAccent() {
        let exam = session([typed()])
        exam.answerTyped("esta")
        XCTAssertEqual(exam.lastRecord?.score, AnswerMatcher.accentsMissedScore)
        XCTAssertEqual(exam.lastTypedKind, .accentsMissed)
        XCTAssertTrue(exam.lastRecord?.isPartial ?? false)
    }

    func testGivingUpScoresZero() {
        let exam = session([typed()])
        exam.giveUp()
        XCTAssertEqual(exam.lastRecord?.score, 0)
        XCTAssertEqual(exam.lastRecord?.given, "")
    }

    func testReorderScoresTheShareOfWordsInPlace() {
        let exam = session([reorder(), reorder()])
        exam.answerOrder(["Hablo", "Spanish"])
        XCTAssertEqual(exam.lastRecord?.score, 1)
        exam.next()
        exam.answerOrder(["Spanish", "Hablo"])
        XCTAssertEqual(exam.lastRecord?.score, 0)
    }

    func testMatchingLosesAQuarterPerMistakeWithFourPairs() {
        let clean = session([match()])
        clean.answerMatch(mistakes: 0)
        XCTAssertEqual(clean.lastRecord?.score, 1)
        let one = session([match()])
        one.answerMatch(mistakes: 1)
        XCTAssertEqual(one.lastRecord?.score, 0.75)
        let many = session([match()])
        many.answerMatch(mistakes: 9)
        XCTAssertEqual(many.lastRecord?.score, 0)
    }

    func testAMatchingAnswerCountsForEveryWordInIt() throws {
        let question = match()
        let exam = session([question])
        exam.answerMatch(mistakes: 2)
        XCTAssertEqual(exam.records[0].words, question.involvedWordIDs)
    }

    func testSpokenAnswersAreGradedLikeTypedOnes() {
        let exam = session([ExamQuestion(kind: .speaking, wordID: word, headword: "hablar", subject: "to speak", format: .spoken(target: "hablar"))])
        exam.answerSpoken("Hablar")
        XCTAssertEqual(exam.lastRecord?.score, 1)
    }

    func testFinishingSavesTheResultOnceAndReportsTheScore() throws {
        var delivered: [([ExamAnswerRecord], TimeInterval)] = []
        let exam = session([choice(), typed()]) { delivered.append(($0, $1)) }
        exam.answerChoice(1)
        exam.next()
        exam.answerTyped("nope")
        XCTAssertEqual(exam.phase, .answered)
        exam.next()
        XCTAssertEqual(exam.phase, .finished)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered[0].0.count, 2)
        XCTAssertEqual(exam.percent, 50)
        XCTAssertEqual(exam.correctCount, 1)
        exam.next()
        XCTAssertEqual(delivered.count, 1)
    }

    func testMissedQuestionsAreTheOnesNotFullyRight() {
        let first = choice(), second = typed()
        let exam = session([first, second])
        exam.answerChoice(1)
        exam.next()
        exam.answerTyped("esta")
        exam.next()
        XCTAssertEqual(exam.missedQuestions.map(\.id), [second.id])
    }

    func testEndingEarlyKeepsWhatWasAnswered() {
        var delivered = 0
        let exam = session([choice(), typed(), reorder()]) { _, _ in delivered += 1 }
        exam.answerChoice(1)
        exam.next()
        exam.endEarly()
        XCTAssertEqual(exam.phase, .finished)
        XCTAssertEqual(exam.records.count, 1)
        XCTAssertEqual(delivered, 1)
        exam.endEarly()
        XCTAssertEqual(delivered, 1)
    }

    func testSkippingAQuestionLeavesItOutOfTheScore() {
        let exam = session([choice(), typed()])
        exam.skipWithoutScore()
        XCTAssertEqual(exam.total, 1)
        XCTAssertEqual(exam.current?.kind, .typeSpanish)
        exam.skipWithoutScore()
        XCTAssertEqual(exam.phase, .finished)
        XCTAssertTrue(exam.records.isEmpty)
    }

    func testAnEmptyExamIsFinishedAtOnce() {
        XCTAssertEqual(session([]).phase, .finished)
    }

    func testScoreBySkillAveragesEachSkill() throws {
        let exam = session([choice(), choice(), typed()])
        exam.answerChoice(1)
        exam.next()
        exam.answerChoice(0)
        exam.next()
        exam.answerTyped("está")
        let skills = exam.scoreBySkill()
        XCTAssertEqual(skills.map(\.skill), [.vocabulary, .typing])
        XCTAssertEqual(skills[0].fraction, 0.5)
        XCTAssertEqual(skills[0].count, 2)
        XCTAssertEqual(skills[1].fraction, 1)
    }

    // MARK: - Written answers

    func testAWrittenAnswerIsScoredByTheAI() async {
        let grader = StubGrader(.success(ExamAIGrade(score: 0.7, corrected: "Hablo mucho.", feedback: "Mind the verb.")))
        let exam = session([written()], grader: grader)
        await exam.answerWritten("  Yo hablo mucho  ")
        XCTAssertEqual(grader.graded.map { $0.answer }, ["Yo hablo mucho"])
        XCTAssertEqual(exam.lastRecord?.score, 0.7)
        XCTAssertEqual(exam.lastRecord?.feedback, "Mind the verb.")
        XCTAssertEqual(exam.lastRecord?.expected, "Hablo mucho.")
        XCTAssertEqual(exam.phase, .answered)
    }

    func testAnOutOfRangeAIScoreIsClamped() async {
        let exam = session([written()], grader: StubGrader(.success(ExamAIGrade(score: 7, corrected: nil, feedback: ""))))
        await exam.answerWritten("hola")
        XCTAssertEqual(exam.lastRecord?.score, 1)
    }

    func testWhenTheAICannotCheckThePersonGradesIt() async {
        let exam = session([written()], grader: StubGrader(.failure(.offline)))
        await exam.answerWritten("hola")
        XCTAssertTrue(exam.needsSelfCheck)
        XCTAssertEqual(exam.phase, .asking)
        exam.selfGrade(0.5)
        XCTAssertEqual(exam.lastRecord?.score, 0.5)
        XCTAssertEqual(exam.lastRecord?.given, "hola")
        XCTAssertFalse(exam.needsSelfCheck)
    }

    func testWithoutAnAIThePersonGradesIt() async {
        let exam = session([written()])
        await exam.answerWritten("hola")
        XCTAssertTrue(exam.needsSelfCheck)
    }

    func testAnEmptyWrittenAnswerIsNotSent() async {
        let grader = StubGrader(.success(ExamAIGrade(score: 1, corrected: nil, feedback: "")))
        let exam = session([written()], grader: grader)
        await exam.answerWritten("   ")
        XCTAssertTrue(grader.graded.isEmpty)
        XCTAssertEqual(exam.phase, .asking)
    }

    func testSelfGradingOnlyWorksWhenAskedFor() {
        let exam = session([choice()])
        exam.selfGrade(1)
        XCTAssertTrue(exam.records.isEmpty)
    }
}
