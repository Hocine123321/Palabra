import CoreText
import XCTest
@testable import Palabra

final class PageFontsTests: XCTestCase {
    func testAmiriIsRegisteredAndUsed() {
        XCTAssertTrue(PageFonts.register())
        for bold in [false, true] {
            let font = PageFonts.ctFont(FontSpec(size: 52, bold: bold))
            let name = CTFontCopyPostScriptName(font) as String
            XCTAssertTrue(name.hasPrefix("Amiri"), "got \(name)")
            XCTAssertEqual(name.hasSuffix("Bold"), bold)
        }
    }

    func testEveryLessonGlyphHasAnAmiriGlyph() {
        let library = BookLibrary.load(from: BundleBookSource())
        var text = ""
        for book in library.books {
            for page in book.pages {
                text += page.lessonTitle + page.page.title + (page.page.dateLabel ?? "")
                for block in page.page.blocks { text += block.texts.map(InlineMarkup.plainText).joined() }
            }
        }
        text += "•—·…0123456789"
        let characters = Set(text.utf16).filter { unit in
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return !isJSWhitespace(scalar) && unit > 31
        }
        XCTAssertFalse(characters.isEmpty)
        for bold in [false, true] {
            let font = PageFonts.ctFont(FontSpec(size: 52, bold: bold))
            // Ask the primary font only (not its cascade): CTFontGetGlyphsForCharacters does not fall back.
            for unit in characters {
                var character = unit
                var glyph: CGGlyph = 0
                XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) && glyph != 0, "no Amiri glyph for U+\(String(unit, radix: 16)) bold=\(bold)")
            }
        }
    }

    func testMeasureIsMonotonicAndCached() {
        let spec = FontSpec(size: 50, bold: false)
        let short = PageFonts.measure("الاستعمار", spec)
        let long = PageFonts.measure("الاستعمار الفرنسي", spec)
        XCTAssertGreaterThan(short, 0)
        XCTAssertGreaterThan(long, short)
        XCTAssertEqual(PageFonts.measure("الاستعمار", spec), short)
        XCTAssertEqual(PageFonts.measure("", spec), 0)
    }

    func testMeasureScalesWithSize() {
        let small = PageFonts.measure("Treaty of Fez", FontSpec(size: 40, bold: false))
        let large = PageFonts.measure("Treaty of Fez", FontSpec(size: 80, bold: false))
        XCTAssertEqual(large / small, 2, accuracy: 0.05)
    }
}
