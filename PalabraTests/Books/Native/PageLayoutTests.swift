import XCTest
@testable import Palabra

final class PageLayoutTests: XCTestCase {
    /// The stand-in the golden numbers were made with: 14 points per UTF-16 unit, whatever the font.
    private let fixed: Measure = { text, _ in Double(text.utf16.count) * 14 }

    private func page(_ blocks: [Block], id: String = "l/p", title: String = "T", date: String? = nil) -> BookPage {
        BookPage(
            id: id, number: 1, chapterID: "c", lessonID: "l", lessonTitle: "Lesson",
            page: LessonPage(id: "p", title: title, dateLabel: date, blocks: blocks), glossary: [:]
        )
    }

    private func rich(_ source: String, width: Double = 1000, rtl: Bool = false, size: Double = 50, measure: Measure? = nil) -> RichLayout {
        RichLayouter.layout(source, measure: measure ?? fixed, width: width, rtl: rtl, style: RichStyle(size: size), slot: "0.p")
    }

    // MARK: Golden pagination

    func testSplitsMatchGoldenWithFixedMeasure() throws {
        let golden = try GoldenFixtures.load()
        XCTAssertFalse(golden.pagination.isEmpty)
        let library = BookLibrary.load(from: BundleBookSource())
        XCTAssertEqual(library.problems, [])
        for item in golden.pagination {
            let book = try XCTUnwrap(library.book(id: item.bookId), item.bookId)
            let source = try XCTUnwrap(book.pages.first { $0.id == item.pageId }, item.pageId)
            let parts = PageLayout.paginate(source, measure: fixed, rtl: book.isRightToLeft, subject: book.subject.rawValue, scale: item.scale)
            let context = "\(item.bookId) \(item.pageId) scale \(item.scale)"
            XCTAssertEqual(parts.count, item.parts.count, context)
            for (ours, theirs) in zip(parts, item.parts) {
                XCTAssertEqual(ours.id, theirs.id, context)
                XCTAssertEqual(ours.baseID, theirs.baseId, context)
                XCTAssertEqual(ours.part, theirs.part, context)
                XCTAssertEqual(ours.parts, theirs.parts, context)
                XCTAssertEqual(ours.scale, theirs.scale, accuracy: 1e-9, context)
                XCTAssertEqual(ours.blocks.map(\.index), theirs.blocks.map(\.index), context)
                for (a, b) in zip(ours.blocks, theirs.blocks) {
                    XCTAssertEqual(a.layout.height, b.height, accuracy: 1e-3, "\(context) block \(b.index)")
                }
            }
        }
    }

    func testPaginationNeverDropsOrReordersABlock() {
        let library = BookLibrary.load(from: BundleBookSource())
        for book in library.books {
            for scale in [0.88, 0.96, 1.0, 1.1, 1.28, 1.42] {
                for source in book.pages {
                    let parts = PageLayout.paginate(source, measure: fixed, rtl: book.isRightToLeft, subject: book.subject.rawValue, scale: scale)
                    XCTAssertEqual(parts.flatMap { $0.blocks.map(\.index) }, Array(source.page.blocks.indices), "\(source.id) @\(scale)")
                    XCTAssertEqual(parts.map(\.part), Array(1...parts.count))
                }
            }
        }
    }

    func testEmptyPageGivesOneBlankPhysicalPage() {
        let parts = PageLayout.paginate(page([]), measure: fixed, rtl: false, subject: "history", scale: 1)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].id, "l/p")
        XCTAssertTrue(parts[0].blocks.isEmpty)
    }

    func testWordWiderThanColumnTerminates() {
        let word = String(repeating: "x", count: 400)
        let parts = PageLayout.paginate(page([.paragraph(word)]), measure: fixed, rtl: true, subject: "history", scale: 1.42)
        XCTAssertEqual(parts.flatMap { $0.blocks.map(\.index) }, [0])
        XCTAssertGreaterThan(parts[0].blocks[0].layout.height, 0)
    }

    func testLongPageSplitsAndTitlesCarryPartNumbers() {
        let blocks = (0..<12).map { Block.paragraph(String(repeating: "word ", count: 120) + "\($0)") }
        let parts = PageLayout.paginate(page(blocks), measure: fixed, rtl: false, subject: "geography", scale: 1)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.first?.id, "l/p~1")
        XCTAssertEqual(parts.last?.parts, parts.count)
        XCTAssertEqual(parts.flatMap { $0.blocks.map(\.index) }, Array(0..<12))
    }

    // MARK: Rich text

    func testWordsAreSplitLikeJavaScript() {
        XCTAssertEqual(splitOnWhitespace(" a  b "), ["", "a", "b", ""])
        XCTAssertEqual(splitOnWhitespace(""), [""])
        XCTAssertEqual(splitOnWhitespace("a\u{00A0}b"), ["a", "b"])
        XCTAssertEqual(splitOnWhitespace("ab"), ["ab"])
    }

    func testTextWrapsAtTheColumnWidth() {
        // Each word is 56 wide; two need 56 + 14 + 56 = 126.
        let r = rich("aaaa bbbb cccc", width: 100)
        XCTAssertEqual(r.lines.count, 3)
        XCTAssertEqual(r.height, 3 * r.lh, accuracy: 1e-9)
        let one = rich("aaaa bbbb", width: 126)
        XCTAssertEqual(one.lines.count, 1)
        XCTAssertEqual(one.lines[0].frags.map(\.x), [0, 70])
    }

    func testEmptyTextIsOneLine() {
        let r = rich("")
        XCTAssertEqual(r.lines.count, 1)
        XCTAssertEqual(r.height, r.lh, accuracy: 1e-9)
    }

    func testBaselineFormula() {
        let r = rich("x", size: 50)
        XCTAssertEqual(r.lh, 92.5, accuracy: 1e-9)
        XCTAssertEqual(r.lines[0].baseline, 50 * 1.18 + (92.5 - 80) * 0.5, accuracy: 1e-9)
    }

    func testRTLRunPositionsMirror() {
        let source = "alpha **beta** [[gamma delta|e]] {{eps|t1}} zeta eta theta"
        let ltr = rich(source, width: 400, rtl: false)
        let rtl = rich(source, width: 400, rtl: true)
        XCTAssertEqual(ltr.lines.count, rtl.lines.count)
        for (a, b) in zip(ltr.lines, rtl.lines) {
            XCTAssertEqual(a.frags.count, b.frags.count)
            for (fa, fb) in zip(a.frags, b.frags) {
                XCTAssertEqual(fb.x, 400 - fa.x - fa.w, accuracy: 1e-9, fa.text)
            }
        }
        for (a, b) in zip(ltr.runs, rtl.runs) {
            XCTAssertEqual(b.x, 400 - a.x - a.w, accuracy: 1e-9)
            XCTAssertEqual(a.w, b.w, accuracy: 1e-9)
        }
    }

    func testRecallRunsMergeAcrossWords() throws {
        let r = rich("see [[Treaty of Fez|k]] now")
        XCTAssertEqual(r.runs.count, 1)
        let run = try XCTUnwrap(r.runs.first)
        XCTAssertEqual(run.text, "Treaty of Fez")
        XCTAssertEqual(run.level, .keyFacts)
        XCTAssertEqual(run.key, "0.p.0")
        XCTAssertEqual(run.x, 3 * 14 + 14, accuracy: 1e-9)
        XCTAssertEqual(run.w, 6 * 14 + 14 + 2 * 14 + 14 + 3 * 14, accuracy: 1e-9)
    }

    func testTwoTargetsOnOneLineAreTwoRuns() {
        let r = rich("[[a|e]] [[b|i]]")
        XCTAssertEqual(r.runs.map(\.key), ["0.p.0", "0.p.1"])
        XCTAssertEqual(r.runs.map(\.level), [.essential, .intensive])
    }

    func testTermHitsPresent() throws {
        let r = rich("{{Fez|fez}} treaty")
        XCTAssertEqual(r.terms.count, 1)
        let hit = try XCTUnwrap(r.terms.first)
        XCTAssertEqual(hit.id, "fez")
        XCTAssertEqual(hit.x, 0, accuracy: 1e-9)
        XCTAssertEqual(hit.w, 42, accuracy: 1e-9)
    }

    func testPunctuationGluedToATargetStaysInOneWord() {
        // "[[1815|e]]،" is one word of two fragments: no space is inserted between them.
        let r = rich("[[1815|e]]،")
        XCTAssertEqual(r.lines[0].frags.count, 2)
        XCTAssertEqual(r.lines[0].frags[1].x, r.lines[0].frags[0].w, accuracy: 1e-9)
    }

    func testBoldFragmentsAskForTheBoldFont() {
        var seen: [FontSpec] = []
        let spy: Measure = { text, font in
            seen.append(font)
            return Double(text.utf16.count) * 14
        }
        _ = rich("plain **strong**", size: 49.6, measure: spy)
        XCTAssertTrue(seen.contains(FontSpec(size: 50, bold: true)))
        XCTAssertTrue(seen.contains(FontSpec(size: 50, bold: false)))
    }

    // MARK: Blocks

    func testEveryBlockTypeLaysOutWithPositiveHeight() {
        let env = LayoutEnv(measure: fixed, rtl: true, scale: 1.1, palette: .history, width: PageGeometry.contentWidth)
        let events: [TimelineEvent] = [
            TimelineEvent(date: "1900", title: "x", detail: "d"),
            TimelineEvent(date: "1901", title: "y", detail: nil)
        ]
        let stats: [StatItem] = [
            StatItem(label: "l", value: "1", unit: nil, note: "n"),
            StatItem(label: "m", value: "2", unit: nil, note: nil),
            StatItem(label: "o", value: "3", unit: nil, note: nil)
        ]
        let row = ComparisonRow(label: "r", cells: ["1", "2"])
        let multiline = ComparisonRow(label: "r", cells: ["x\ny"])
        let stages: [FlowStage] = [FlowStage(label: "s", nodes: ["n"]), FlowStage(label: nil, nodes: ["m"])]
        let steps: [ProcessStep] = [ProcessStep(title: "a", detail: "b"), ProcessStep(title: "c", detail: nil)]
        let definitions: [DefinitionItem] = [DefinitionItem(id: nil, term: "t", definition: "d")]
        var blocks: [Block] = []
        blocks.append(.heading(text: "H", level: 1))
        blocks.append(.heading(text: "H", level: 3))
        blocks.append(.paragraph("p"))
        blocks.append(.list(title: "t", items: ["a", "b"], ordered: true))
        blocks.append(.keyPoint(label: "l", text: "k"))
        blocks.append(.quote(text: "q", source: "s"))
        blocks.append(.timeline(title: nil, events: events))
        blocks.append(.stats(title: nil, items: stats))
        blocks.append(.comparison(title: nil, corner: nil, columns: ["a", "b"], rows: [row]))
        blocks.append(.comparison(title: nil, corner: nil, columns: [], rows: [multiline]))
        blocks.append(.causeEffect(title: "c", stages: stages))
        blocks.append(.process(title: nil, steps: steps))
        blocks.append(.definitions(title: nil, items: definitions))
        blocks.append(.image(ImagePanel(name: "i", caption: "c", alt: "a", style: nil)))
        blocks.append(.unsupported(type: "future"))
        for (i, block) in blocks.enumerated() {
            let layout = BlockLayouter.layout(block, index: i, env: env)
            XCTAssertGreaterThan(layout.height, 0, "\(block)")
            XCTAssertFalse(layout.parts.isEmpty, "\(block)")
            XCTAssertEqual(layout.index, i)
        }
    }

    func testBlockHeightsGrowWithScale() {
        func height(_ scale: Double) -> Double {
            let env = LayoutEnv(measure: fixed, rtl: false, scale: scale, palette: .history, width: PageGeometry.contentWidth)
            return BlockLayouter.layout(.paragraph(String(repeating: "word ", count: 100)), index: 0, env: env).height
        }
        XCTAssertLessThan(height(0.96), height(1.42))
    }

    func testHeadingRuleSitsAtTheStartEdge() {
        let ltr = LayoutEnv(measure: fixed, rtl: false, scale: 1, palette: .history, width: 1000)
        let rtl = LayoutEnv(measure: fixed, rtl: true, scale: 1, palette: .history, width: 1000)
        func ruleX(_ env: LayoutEnv) -> Double? {
            for part in BlockLayouter.layout(.heading(text: "H", level: 2), index: 0, env: env).parts {
                if case .rect(let x, _, _, _, _, _, _, _) = part { return x }
            }
            return nil
        }
        XCTAssertEqual(ruleX(ltr), 0)
        XCTAssertEqual(ruleX(rtl), 910)
    }

    // MARK: Header

    func testHeaderLongTitleWrapsAndPushesTheBodyDown() {
        let short = PageLayout.header(HeaderInfo(title: "Short", dateLabel: nil, part: 1, parts: 1), measure: fixed)
        let long = PageLayout.header(HeaderInfo(title: String(repeating: "word ", count: 40), dateLabel: "1900", part: 1, parts: 1), measure: fixed)
        XCTAssertEqual(short.lines, ["Short"])
        XCTAssertGreaterThan(long.lines.count, 1)
        XCTAssertGreaterThan(long.bodyY, short.bodyY)
        XCTAssertNil(short.dateY)
        XCTAssertNotNil(long.dateY)
    }

    func testHeaderOfALaterPartIsSmallerAndNumbered() {
        let second = PageLayout.header(HeaderInfo(title: "Title", dateLabel: "1900", part: 2, parts: 3), measure: fixed)
        XCTAssertEqual(second.size, 54)
        XCTAssertEqual(second.lines, ["Title · 2/3"])
        XCTAssertNil(second.dateY)
    }
}
