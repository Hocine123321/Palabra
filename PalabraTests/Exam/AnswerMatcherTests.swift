import XCTest
@testable import Palabra

final class AnswerMatcherTests: XCTestCase {
    func testNormalizeLowercasesAndDropsPunctuationButKeepsAccents() {
        XCTAssertEqual(AnswerMatcher.normalize("  ¡Hablar!  "), "hablar")
        XCTAssertEqual(AnswerMatcher.normalize("Está   AQUÍ."), "está aquí")
    }

    func testFoldRemovesAccentsAndTheTilde() {
        XCTAssertEqual(AnswerMatcher.fold("pingüino"), "pinguino")
        XCTAssertEqual(AnswerMatcher.fold("Niño"), "nino")
    }

    func testExactAnswerScoresOneWhateverTheCaseAndPunctuation() {
        let grade = AnswerMatcher.grade(typed: "  HABLAR. ", accepted: ["hablar"])
        XCTAssertEqual(grade, AnswerMatcher.Grade(kind: .exact, score: 1))
    }

    func testMissingAccentIsPartialCredit() {
        let grade = AnswerMatcher.grade(typed: "esta", accepted: ["está"])
        XCTAssertEqual(grade.kind, .accentsMissed)
        XCTAssertEqual(grade.score, AnswerMatcher.accentsMissedScore)
    }

    func testOneTypoInALongerWordIsPartialCredit() {
        let grade = AnswerMatcher.grade(typed: "hablr", accepted: ["hablar"])
        XCTAssertEqual(grade.kind, .typo)
        XCTAssertEqual(grade.score, AnswerMatcher.typoScore)
    }

    func testShortWordsAllowNoTypo() {
        XCTAssertEqual(AnswerMatcher.grade(typed: "oso", accepted: ["ojo"]).kind, .wrong)
    }

    func testLongerWordsAllowMoreLettersOff() {
        XCTAssertEqual(AnswerMatcher.grade(typed: "escribier", accepted: ["escribir"]).kind, .typo)
        XCTAssertEqual(AnswerMatcher.grade(typed: "extraordinaro", accepted: ["extraordinario"]).kind, .typo)
        XCTAssertEqual(AnswerMatcher.grade(typed: "extraordinro", accepted: ["extraordinario"]).kind, .typo)
    }

    func testWrongAndEmptyAnswersScoreZero() {
        XCTAssertEqual(AnswerMatcher.grade(typed: "gato", accepted: ["perro"]).score, 0)
        XCTAssertEqual(AnswerMatcher.grade(typed: "   ", accepted: ["perro"]), AnswerMatcher.Grade(kind: .wrong, score: 0))
    }

    func testEnglishAnswersMayLeaveOutToAndTheAndEitherMeaningIsRight() {
        let accepted = ["to speak; to talk (informal)"]
        XCTAssertEqual(AnswerMatcher.grade(typed: "speak", accepted: accepted, english: true).score, 1)
        XCTAssertEqual(AnswerMatcher.grade(typed: "To Talk", accepted: accepted, english: true).score, 1)
        XCTAssertEqual(AnswerMatcher.grade(typed: "eat", accepted: accepted, english: true).score, 0)
    }

    func testBracketsAreExplanationsNotPartOfTheAnswer() {
        XCTAssertEqual(AnswerMatcher.alternatives(of: "to speak; to talk (informal)"), ["to speak", "to talk"])
        XCTAssertEqual(AnswerMatcher.alternatives(of: "house, home"), ["house", "home"])
    }

    func testTheBestAcceptedAnswerWins() {
        let grade = AnswerMatcher.grade(typed: "esta", accepted: ["hola", "está"])
        XCTAssertEqual(grade.kind, .accentsMissed)
    }

    func testEditDistance() {
        XCTAssertEqual(AnswerMatcher.distance("kitten", "sitting"), 3)
        XCTAssertEqual(AnswerMatcher.distance("", "abc"), 3)
        XCTAssertEqual(AnswerMatcher.distance("same", "same"), 0)
    }

    func testOrderScoreIsTheShareOfWordsInPlace() {
        let answer = ["Hablo", "español", "con", "amigos"]
        XCTAssertEqual(AnswerMatcher.orderScore(given: answer, answer: answer), 1)
        XCTAssertEqual(AnswerMatcher.orderScore(given: ["Hablo", "español", "amigos", "con"], answer: answer), 0.5)
        XCTAssertEqual(AnswerMatcher.orderScore(given: ["Hablo"], answer: answer), 0.25)
        XCTAssertEqual(AnswerMatcher.orderScore(given: [], answer: []), 0)
    }

    func testTokensKeepPunctuationAttached() {
        XCTAssertEqual(AnswerMatcher.tokens(of: "¿Cómo estás?  Bien."), ["¿Cómo", "estás?", "Bien."])
    }
}

final class ClozeFinderTests: XCTestCase {
    func testBlanksAConjugatedFormAndKeepsTheOriginalSentence() throws {
        let cloze = try XCTUnwrap(ClozeFinder.make(sentence: "Hablo español con mis amigos.", candidates: ["hablar", "hablo"]))
        XCTAssertEqual(cloze.blanked, "_____ español con mis amigos.")
        XCTAssertEqual(cloze.answer, "Hablo")
        XCTAssertEqual(cloze.full, "Hablo español con mis amigos.")
    }

    func testOnlyWholeWordsAreBlanked() {
        XCTAssertNil(ClozeFinder.make(sentence: "Como pan todos los días.", candidates: ["om"]))
    }

    func testAccentsDoNotHideAMatch() throws {
        let cloze = try XCTUnwrap(ClozeFinder.make(sentence: "Hoy es un buen día.", candidates: ["dia"]))
        XCTAssertEqual(cloze.answer, "día")
    }

    func testTheLongestCandidateIsTriedFirst() throws {
        let cloze = try XCTUnwrap(ClozeFinder.make(sentence: "Quiero comer pan ahora.", candidates: ["como", "comer"]))
        XCTAssertEqual(cloze.answer, "comer")
    }

    func testVeryShortSentencesAreNotUsed() {
        XCTAssertNil(ClozeFinder.make(sentence: "Hablo mucho.", candidates: ["hablo"]))
    }
}
