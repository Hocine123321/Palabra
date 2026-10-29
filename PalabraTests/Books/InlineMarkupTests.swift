import XCTest
@testable import Palabra

final class InlineMarkupTests: XCTestCase {
    func testPlainTextIsOneSegment() {
        XCTAssertEqual(InlineMarkup.parse("just words"), [.text("just words")])
    }

    func testTermIsReadWithItsId() {
        XCTAssertEqual(
            InlineMarkup.parse("a {{market|markets}} b"),
            [.text("a "), .term(text: "market", id: "markets"), .text(" b")]
        )
    }

    func testRecallLevelsAndDefault() {
        let segments = InlineMarkup.parse("[[1815|e]] [[Vienna|k]] [[trade|i]] [[plain]]")
        XCTAssertEqual(segments, [
            .recall(text: "1815", level: .essential, index: 0), .text(" "),
            .recall(text: "Vienna", level: .keyFacts, index: 1), .text(" "),
            .recall(text: "trade", level: .intensive, index: 2), .text(" "),
            .recall(text: "plain", level: .keyFacts, index: 3)
        ])
    }

    func testBold() {
        XCTAssertEqual(InlineMarkup.parse("a **b** c"), [.text("a "), .bold("b"), .text(" c")])
    }

    func testUnclosedMarkerStaysAsTextAndIsReported() {
        let scan = InlineMarkup.scan("see [[open")
        XCTAssertEqual(scan.segments, [.text("see [[open")])
        XCTAssertEqual(scan.problems, ["unclosed [["])
    }

    func testUnknownLevelIsReportedAndTheTextStaysWhole() {
        let scan = InlineMarkup.scan("[[word|x]]")
        XCTAssertEqual(scan.segments, [.recall(text: "word|x", level: .keyFacts, index: 0)])
        XCTAssertEqual(scan.problems.count, 1)
    }

    func testTermWithoutIdIsReported() {
        let scan = InlineMarkup.scan("{{word}}")
        XCTAssertEqual(scan.segments, [.text("{{word}}")])
        XCTAssertEqual(scan.problems.count, 1)
    }

    func testArabicTextWithMarkup() {
        let segments = InlineMarkup.parse("ظهور [[الكشوفات الجغرافية|k]] في {{الأسواق|markets}}.")
        XCTAssertEqual(segments, [
            .text("ظهور "),
            .recall(text: "الكشوفات الجغرافية", level: .keyFacts, index: 0),
            .text(" في "),
            .term(text: "الأسواق", id: "markets"),
            .text(".")
        ])
    }

    func testPlainTextRemovesEveryMarker() {
        XCTAssertEqual(InlineMarkup.plainText("a [[b|e]] {{c|id}} **d**"), "a b c d")
    }

    func testBracketsThatAreNotMarkersSurvive() {
        XCTAssertEqual(InlineMarkup.parse("word […] more"), [.text("word […] more")])
    }

    func testRecallIndexCountsWithinOneString() {
        let indexes = InlineMarkup.parse("[[a|e]] x [[b|e]]").compactMap { segment -> Int? in
            if case .recall(_, _, let index) = segment { return index }
            return nil
        }
        XCTAssertEqual(indexes, [0, 1])
    }

    func testLevelsConcealEasierLevelsToo() {
        XCTAssertTrue(RecallLevel.essential.conceals(.essential))
        XCTAssertFalse(RecallLevel.essential.conceals(.keyFacts))
        XCTAssertTrue(RecallLevel.keyFacts.conceals(.essential))
        XCTAssertTrue(RecallLevel.keyFacts.conceals(.keyFacts))
        XCTAssertFalse(RecallLevel.keyFacts.conceals(.intensive))
        XCTAssertTrue(RecallLevel.intensive.conceals(.essential))
        XCTAssertTrue(RecallLevel.intensive.conceals(.keyFacts))
        XCTAssertTrue(RecallLevel.intensive.conceals(.intensive))
    }
}
