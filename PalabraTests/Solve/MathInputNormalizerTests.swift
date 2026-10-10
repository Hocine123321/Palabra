import XCTest
@testable import Palabra

final class MathInputNormalizerTests: XCTestCase {
    private func n(_ text: String) -> String { MathInputNormalizer.normalize(text) }

    func testPlainTextIsKept() {
        XCTAssertEqual(n("x^2 - 4 = 0"), "x^2 - 4 = 0")
        XCTAssertEqual(n("  integrate sin(x) dx  "), "integrate sin(x) dx")
    }

    func testOperatorsAreRewritten() {
        XCTAssertEqual(n("3 \u{00D7} 4 \u{00F7} 2 \u{2212} 1"), "3 * 4 / 2 - 1")
        XCTAssertEqual(n("a \u{2264} b, c \u{2265} d, e \u{2260} f"), "a <= b, c >= d, e != f")
        XCTAssertEqual(n("2\u{03C0}r"), "2pir")
    }

    func testSuperscriptsBecomeExponents() {
        XCTAssertEqual(n("x\u{00B2} + y\u{00B3}"), "x^2 + y^3")
        XCTAssertEqual(n("x\u{00B9}\u{2070}"), "x^10")
    }

    func testSquareRoots() {
        XCTAssertEqual(n("\u{221A}(x+1)"), "sqrt(x+1)")
        XCTAssertEqual(n("\u{221A}2 + \u{221A} x"), "sqrt(2) + sqrt(x)")
    }

    func testLinesAndSpacesCollapse() {
        XCTAssertEqual(n("x + 1\n   = 3"), "x + 1 = 3")
    }

    func testQuestionNumberingIsStripped() {
        XCTAssertEqual(n("1. x + 2 = 5"), "x + 2 = 5")
        XCTAssertEqual(n("3) 2x = 8"), "2x = 8")
        XCTAssertEqual(n("a) x - 1 = 0"), "x - 1 = 0")
        XCTAssertEqual(n("Q4: 5 + 5"), "5 + 5")
    }

    func testMathThatLooksLikeNumberingIsKept() {
        XCTAssertEqual(n("(1) + 2"), "(1) + 2")
        XCTAssertEqual(n("2.5 + 3"), "2.5 + 3")
        XCTAssertEqual(n("f(x) = 2"), "f(x) = 2")
    }

    func testLengthIsCapped() {
        XCTAssertEqual(n(String(repeating: "x", count: 1000)).count, MathInputNormalizer.maxLength)
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(n("  \n "), "")
    }

    func testKeyIgnoresCaseAndSpaces() {
        XCTAssertEqual(MathInputNormalizer.key(for: "X^2 - 4 = 0"), MathInputNormalizer.key(for: "x^2-4=0"))
        XCTAssertNotEqual(MathInputNormalizer.key(for: "x^2-4=0"), MathInputNormalizer.key(for: "x^2-9=0"))
    }
}
