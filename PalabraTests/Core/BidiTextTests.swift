import XCTest
@testable import Palabra

final class BidiTextTests: XCTestCase {
    private let lri = BidiText.leftToRightIsolate
    private let pdi = BidiText.popIsolate

    func testDetectsArabicLetters() {
        XCTAssertTrue(BidiText.containsArabic("الجواب 4"))
        XCTAssertFalse(BidiText.containsArabic("x = 4"))
        XCTAssertFalse(BidiText.containsArabic(""))
    }

    func testFormulasInsideArabicTextAreIsolatedEachOnItsOwn() {
        let line = "الجواب x = -2 أو x = 2"
        XCTAssertEqual(
            BidiText.isolateFormulas(in: line),
            "الجواب \(lri)x = -2\(pdi) أو \(lri)x = 2\(pdi)"
        )
    }

    func testSentencePunctuationStaysOutsideTheFormula() {
        XCTAssertEqual(BidiText.isolateFormulas(in: "الناتج 4."), "الناتج \(lri)4\(pdi).")
    }

    func testARunWithoutLettersOrDigitsIsLeftAlone() {
        XCTAssertEqual(BidiText.isolateFormulas(in: "هذا - ذلك"), "هذا - ذلك")
    }

    func testArabicWithoutAnyFormulaIsUnchanged() {
        XCTAssertEqual(BidiText.isolateFormulas(in: "لا يوجد حل"), "لا يوجد حل")
    }

    func testFormulaLinesAreIsolatedOnlyOnARightToLeftScreen() {
        XCTAssertEqual(BidiText.display("x^2 - 4 = 0", rightToLeftLayout: false), "x^2 - 4 = 0", "English screens show the text exactly as written")
        XCTAssertEqual(BidiText.display("x^2 - 4 = 0", rightToLeftLayout: true), "\(lri)x^2 - 4 = 0\(pdi)")
    }

    func testArabicLinesIsolateTheirFormulasOnAnyScreen() {
        let line = "نعوّض x = 3"
        XCTAssertEqual(BidiText.display(line, rightToLeftLayout: false), BidiText.display(line, rightToLeftLayout: true))
        XCTAssertTrue(BidiText.display(line, rightToLeftLayout: false).contains("\(lri)x = 3\(pdi)"))
    }

    func testIsolatingNothingStaysNothing() {
        XCTAssertEqual(BidiText.isolated(""), "")
    }

    func testNumberedLinesSplitIntoNumberAndText() {
        let parsed = BidiText.numberedLine("2. نعوّض x = 3")
        XCTAssertEqual(parsed?.number, 2)
        XCTAssertEqual(parsed?.text, "نعوّض x = 3")
        XCTAssertEqual(BidiText.numberedLine("12) text")?.number, 12)
        XCTAssertNil(BidiText.numberedLine("(a) x = 3"))
        XCTAssertNil(BidiText.numberedLine("1.5 is a number"))
        XCTAssertNil(BidiText.numberedLine("3. "))
    }
}
