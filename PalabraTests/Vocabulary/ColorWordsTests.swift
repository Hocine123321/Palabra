import XCTest
@testable import Palabra

final class ColorWordsTests: XCTestCase {
    private func family(_ word: String) -> ColorFamily? { ColorWords.match(word)?.family }

    func testBaseColours() {
        XCTAssertEqual(family("rojo"), .red)
        XCTAssertEqual(family("azul"), .blue)
        XCTAssertEqual(family("verde"), .green)
        XCTAssertEqual(family("amarillo"), .yellow)
        XCTAssertEqual(family("negro"), .black)
        XCTAssertEqual(family("blanco"), .white)
        XCTAssertEqual(family("celeste"), .lightBlue)
    }

    func testMatchingIgnoresCaseAndAccents() {
        XCTAssertEqual(family("Marrón"), .brown)
        XCTAssertEqual(family("marron"), .brown)
        XCTAssertEqual(family("  CAFÉ "), .brown)
        XCTAssertEqual(family("púrpura"), .purple)
    }

    func testGenderAndNumber() {
        XCTAssertEqual(family("roja"), .red)
        XCTAssertEqual(family("rojos"), .red)
        XCTAssertEqual(family("rojas"), .red)
        XCTAssertEqual(family("azules"), .blue)
        XCTAssertEqual(family("grises"), .gray)
        XCTAssertEqual(family("marrones"), .brown)
        XCTAssertEqual(family("negras"), .black)
        XCTAssertEqual(family("rosas"), .pink)
        XCTAssertEqual(family("naranjas"), .orange)
    }

    func testShadeWords() {
        XCTAssertEqual(ColorWords.match("azul claro"), ColorWordMatch(family: .blue, shade: .light))
        XCTAssertEqual(ColorWords.match("verde oscuro"), ColorWordMatch(family: .green, shade: .deep))
        XCTAssertEqual(ColorWords.match("rosa pastel"), ColorWordMatch(family: .pink, shade: .light))
        XCTAssertEqual(ColorWords.match("rojo brillante"), ColorWordMatch(family: .red, shade: .normal))
    }

    func testNamedShades() {
        XCTAssertEqual(ColorWords.match("azul marino"), ColorWordMatch(family: .navy, shade: .normal))
        XCTAssertEqual(ColorWords.match("azul cielo"), ColorWordMatch(family: .lightBlue, shade: .normal))
        XCTAssertEqual(ColorWords.match("verde lima"), ColorWordMatch(family: .lime, shade: .normal))
        XCTAssertEqual(ColorWords.match("verde oliva"), ColorWordMatch(family: .green, shade: .deep))
    }

    func testNamedShadeOnlyAfterItsOwnColour() {
        XCTAssertNil(ColorWords.match("rojo marino"))
        XCTAssertNil(ColorWords.match("amarillo lima"))
    }

    func testNonColourWordsAndPhrasesAreNotMatched() {
        XCTAssertNil(ColorWords.match("casa"))
        XCTAssertNil(ColorWords.match("rojo de ira"))
        XCTAssertNil(ColorWords.match("blanco y negro"))
        XCTAssertNil(ColorWords.match("ojo"))
        XCTAssertNil(ColorWords.match("las rosas de mi jardín"))
        XCTAssertNil(ColorWords.match(""))
        XCTAssertNil(ColorWords.match("   "))
    }

    func testFeminineEndingDoesNotInventColours() {
        // "casa" would become "caso" and "pelota" "pelot": neither is in the table.
        XCTAssertNil(ColorWords.match("pelota"))
        XCTAssertNil(ColorWords.match("mesa"))
    }

    func testEveryFamilyHasAnEntry() {
        let reachable: Set<ColorFamily> = [
            .red, .orange, .yellow, .lime, .green, .teal, .lightBlue, .blue, .navy, .purple, .lavender,
            .pink, .maroon, .brown, .beige, .gray, .black, .white, .gold, .silver
        ]
        XCTAssertEqual(reachable.count, ColorFamily.allCases.count)
        let words = ["rojo", "naranja", "amarillo", "verde lima", "verde", "turquesa", "celeste", "azul", "azul marino",
                     "morado", "lila", "rosa", "granate", "marrón", "beige", "gris", "negro", "blanco", "dorado", "plateado"]
        let found = Set(words.compactMap { ColorWords.match($0)?.family })
        XCTAssertEqual(found, reachable)
    }
}
