import XCTest
@testable import Palabra

final class ExamBuilderTests: XCTestCase {
    private let library = ExamFixtures.library()

    private func build(
        _ config: ExamConfig, seed: UInt64 = 7, pool: [ExamWord]? = nil, stats: [UUID: ExamWordStat] = [:],
        speech: Bool = false, ai: [UUID: ExamAIItem] = [:]
    ) -> [ExamQuestion] {
        var builder = ExamBuilder(rng: SeededGenerator(seed: seed), pool: pool ?? library, capabilities: ExamCapabilities(speech: speech), aiItems: ai)
        return builder.build(config: config, stats: stats)
    }

    private func config(_ skills: Set<ExamSkill>, count: Int = 10, source: ExamSource = .all, ai: Bool = false) -> ExamConfig {
        ExamConfig(source: source, questionCount: count, skills: skills, useAI: ai)
    }

    private func signature(_ questions: [ExamQuestion]) -> [String] {
        questions.map { "\($0.kind.rawValue)|\($0.headword)|\($0.subject)|\($0.expectedText)" }
    }

    func testBuildsTheRequestedNumberOfQuestions() {
        XCTAssertEqual(build(config(ExamFixtures.offlineSkills, count: 10)).count, 10)
    }

    func testEachWordIsAskedAtMostTwiceSoALongExamStopsAtTwiceTheWords() {
        XCTAssertEqual(build(config(ExamFixtures.offlineSkills, count: 30)).count, library.count * 2)
    }

    func testTheSameSeedMakesTheSameExam() {
        let first = build(config(ExamFixtures.offlineSkills, count: 12), seed: 42)
        let second = build(config(ExamFixtures.offlineSkills, count: 12), seed: 42)
        XCTAssertEqual(signature(first), signature(second))
        XCTAssertNotEqual(signature(first), signature(build(config(ExamFixtures.offlineSkills, count: 12), seed: 43)))
    }

    func testChoiceQuestionsHaveTheirAnswerAmongUniqueOptions() {
        let questions = build(config([.vocabulary, .grammar], count: 20), seed: 3)
        var seenChoice = false
        for question in questions {
            guard case .choice(let options, let correct) = question.format else { continue }
            seenChoice = true
            XCTAssertTrue(options.indices.contains(correct))
            XCTAssertGreaterThanOrEqual(options.count, 2)
            XCTAssertLessThanOrEqual(options.count, ExamBuilder<SeededGenerator>.maxOptions)
            XCTAssertEqual(Set(options.map(AnswerMatcher.fold)).count, options.count, "no two options alike: \(options)")
        }
        XCTAssertTrue(seenChoice)
    }

    func testMeaningChoiceHoldsTheRightTranslation() throws {
        let questions = build(config([.vocabulary], count: 20), seed: 5).filter { $0.kind == .meaningChoice }
        XCTAssertFalse(questions.isEmpty)
        for question in questions {
            let word = try XCTUnwrap(library.first { $0.id == question.wordID })
            guard case .choice(let options, let correct) = question.format else { return XCTFail("not a choice") }
            XCTAssertEqual(options[correct], word.primaryTranslation)
            XCTAssertEqual(question.subject, word.headword)
        }
    }

    func testTypingQuestionsAcceptTheWordOrItsMeanings() throws {
        let questions = build(config([.typing], count: 16), seed: 9)
        XCTAssertEqual(Set(questions.map(\.kind)), [.typeSpanish, .typeMeaning])
        for question in questions {
            let word = try XCTUnwrap(library.first { $0.id == question.wordID })
            guard case .typed(let accepted, let english) = question.format else { return XCTFail("not typed") }
            if question.kind == .typeSpanish {
                XCTAssertEqual(accepted, [word.headword])
                XCTAssertFalse(english)
            } else {
                XCTAssertEqual(accepted, word.translations)
                XCTAssertTrue(english)
            }
        }
    }

    func testFillBlankBlanksTheWordAndKeepsTheAnswer() {
        let questions = build(config([.grammar], count: 30), seed: 11).filter { $0.kind == .fillBlank }
        XCTAssertFalse(questions.isEmpty)
        for question in questions {
            XCTAssertTrue(question.subject.contains(ClozeFinder.blank))
            switch question.format {
            case .choice(let options, let correct):
                XCTAssertTrue(question.explanation?.contains(options[correct]) ?? false, "the sentence holds the answer")
            case .typed(let accepted, _):
                XCTAssertTrue(question.explanation?.contains(accepted[0]) ?? false)
            default:
                XCTFail("unexpected format")
            }
        }
    }

    func testReorderShufflesTheSentenceIntoADifferentOrder() throws {
        let questions = build(config([.grammar], count: 30), seed: 13).filter { $0.kind == .reorder }
        XCTAssertFalse(questions.isEmpty)
        for question in questions {
            guard case .reorder(let tokens, let answer) = question.format else { return XCTFail("not reorder") }
            XCTAssertEqual(tokens.sorted(), answer.sorted())
            XCTAssertNotEqual(tokens.map(AnswerMatcher.fold), answer.map(AnswerMatcher.fold))
            XCTAssertEqual(answer.joined(separator: " "), question.explanation)
        }
    }

    func testMatchingAppearsAtMostOncePerFifteenQuestionsAndHasEnoughPairs() throws {
        let questions = build(config([.vocabulary], count: 20), seed: 17)
        let matches = questions.filter { $0.kind == .matchPairs }
        XCTAssertLessThanOrEqual(matches.count, 1)
        for question in matches {
            guard case .match(let pairs) = question.format else { return XCTFail("not a match") }
            XCTAssertGreaterThanOrEqual(pairs.count, 4)
            XCTAssertEqual(question.involvedWordIDs, pairs.map(\.wordID))
            XCTAssertEqual(Set(pairs.map(\.left)).count, pairs.count)
        }
    }

    func testListeningPlaysTheTextAndExpectsItTyped() {
        let questions = build(config([.listening], count: 8), seed: 19)
        XCTAssertEqual(questions.count, 8)
        for question in questions {
            XCTAssertEqual(question.kind, .listening)
            XCTAssertEqual(question.subject, "")
            guard case .typed(let accepted, _) = question.format else { return XCTFail("not typed") }
            XCTAssertEqual(accepted, [question.speakText ?? ""])
        }
    }

    func testSpeakingNeedsSpeechRecognition() {
        XCTAssertTrue(build(config([.speaking], count: 5), speech: false).isEmpty)
        let spoken = build(config([.speaking], count: 5), speech: true)
        XCTAssertEqual(spoken.count, 5)
        for question in spoken {
            guard case .spoken(let target) = question.format else { return XCTFail("not spoken") }
            XCTAssertEqual(target, question.headword)
        }
    }

    func testWritingNeedsAI() {
        XCTAssertTrue(build(config([.writing], count: 5)).isEmpty)
        let written = build(config([.writing], count: 5, ai: true))
        XCTAssertEqual(written.count, 5)
        XCTAssertTrue(written.allSatisfy { if case .written = $0.format { return true } else { return false } })
    }

    func testAIMaterialMakesTranslateQuestionsAndFreshBlanks() throws {
        let hablar = try XCTUnwrap(library.first { $0.headword == "hablar" })
        var item = ExamAIItem(wordID: hablar.id)
        item.translatePrompt = "I speak with my friend."
        item.reference = "Hablo con mi amigo."
        item.cloze = "Ella _____ tres idiomas."
        item.clozeAnswer = "habla"
        item.clozeEnglish = "She speaks three languages."
        let questions = build(config([.writing], count: 8, source: .words([hablar.id]), ai: true), ai: [hablar.id: item])
        let translate = questions.first { $0.kind == .translate }
        XCTAssertEqual(translate?.subject, "I speak with my friend.")
        if case .written(let reference)? = translate?.format { XCTAssertEqual(reference, "Hablo con mi amigo.") } else { XCTFail("not written") }

        // One word gets two of the three grammar kinds; over a few seeds the blank turns up.
        let blanks = (1...20).flatMap { seed in
            build(config([.grammar], count: 2, source: .words([hablar.id])), seed: UInt64(seed), ai: [hablar.id: item]).filter { $0.kind == .fillBlank }
        }
        XCTAssertFalse(blanks.isEmpty)
        XCTAssertTrue(blanks.allSatisfy { $0.subject == "Ella _____ tres idiomas." })
    }

    func testSourcesChooseTheRightWords() {
        let review = Set(library.filter(\.needsReview).map(\.id))
        XCTAssertEqual(Set(build(config([.typing], count: 4, source: .needReview)).map(\.wordID)), review)

        let food = Set(library.filter { $0.category == "Food" }.map(\.id))
        XCTAssertEqual(Set(build(config([.typing], count: 4, source: .section("Food"))).map(\.wordID)), food)

        let common = Set(library.filter { $0.tags.contains("common") }.map(\.id))
        XCTAssertEqual(Set(build(config([.typing], count: 4, source: .tag("COMMON"))).map(\.wordID)), common)

        let newest = Set(library.sorted { $0.createdAt > $1.createdAt }.prefix(3).map(\.id))
        XCTAssertEqual(Set(build(config([.typing], count: 3, source: .recent)).map(\.wordID)), newest)

        let chosen = Array(library.prefix(2).map(\.id))
        XCTAssertEqual(Set(build(config([.typing], count: 2, source: .words(chosen))).map(\.wordID)), Set(chosen))
    }

    func testWeakestFirstPicksTheWordsGotWrongMost() {
        var stats: [UUID: ExamWordStat] = [:]
        for (index, word) in library.enumerated() {
            stats[word.id] = ExamWordStat(attempts: 4, scoreSum: index < 3 ? 0.4 : 4, lastSeen: Date())
        }
        let questions = build(config([.typing], count: 3, source: .weakest), stats: stats)
        XCTAssertEqual(Set(questions.map(\.wordID)), Set(library.prefix(3).map(\.id)))
    }

    func testPlannedWordsAreTheWordsTheExamUses() {
        let cfg = config([.typing], count: 5)
        var planner = ExamBuilder(rng: SeededGenerator(seed: 21), pool: library)
        let planned = planner.plannedWords(config: cfg, stats: [:])
        XCTAssertEqual(Set(planned.map(\.id)), Set(build(cfg, seed: 21).map(\.wordID)))
    }

    func testNothingToAskGivesNoQuestions() {
        XCTAssertTrue(build(config([])).isEmpty)
        XCTAssertTrue(build(config([.typing]), pool: []).isEmpty)
        XCTAssertTrue(build(config([.typing], source: .needReview), pool: library.map { word in
            ExamFixtures.word(word.headword, word.translations)
        }).isEmpty)
    }

    func testAnExamMixesSeveralKindsOfQuestion() {
        let kinds = Set(build(config(ExamFixtures.offlineSkills, count: 20), seed: 23).map(\.kind))
        XCTAssertGreaterThanOrEqual(kinds.count, 5)
    }

    func testAWordIsNotAskedTheSameWayTwiceInOneExam() {
        let questions = build(config(ExamFixtures.offlineSkills, count: 16), seed: 29)
        var seen = Set<String>()
        for question in questions where question.kind != .matchPairs {
            XCTAssertTrue(seen.insert("\(question.wordID)|\(question.kind.rawValue)").inserted, "\(question.headword) \(question.kind)")
        }
    }
}
