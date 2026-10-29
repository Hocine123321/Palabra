import XCTest
@testable import Palabra

final class LessonDecodingTests: XCTestCase {
    private func decodeBlocks(_ json: String) throws -> [Block] {
        try JSONDecoder().decode([Block].self, from: Data(json.utf8))
    }

    func testEveryBlockKindDecodes() throws {
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(BookFixtures.rivers.utf8))
        let blocks = lesson.pages[0].blocks
        XCTAssertEqual(blocks.count, 5)
        guard case .stats(_, let items) = blocks[0] else { return XCTFail("stats") }
        XCTAssertEqual(items.first?.unit, "كم")
        guard case .comparison(_, let corner, let columns, let rows) = blocks[1] else { return XCTFail("comparison") }
        XCTAssertEqual(corner, "النهر")
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(rows.first?.cells, ["6650", "المتوسط"])
        guard case .process(_, let steps) = blocks[2] else { return XCTFail("process") }
        XCTAssertEqual(steps.map(\.title), ["المنبع", "المصب"])
        guard case .image(let panel) = blocks[3] else { return XCTFail("image") }
        XCTAssertEqual(panel.name, "map-nile")
        XCTAssertEqual(panel.style, "map")
    }

    func testHeadingDefaultsToLevelTwo() throws {
        let blocks = try decodeBlocks(#"[{"type":"heading","text":"T"}]"#)
        XCTAssertEqual(blocks, [.heading(text: "T", level: 2)])
    }

    func testCauseEffectDecodesStagesWithOptionalLabels() throws {
        let blocks = try decodeBlocks(#"[{"type":"causeEffect","title":"X","stages":[{"label":"Causes","nodes":["a","b"]},{"nodes":["c"]}]}]"#)
        XCTAssertEqual(blocks, [.causeEffect(title: "X", stages: [FlowStage(label: "Causes", nodes: ["a", "b"]), FlowStage(label: nil, nodes: ["c"])])])
    }

    func testUnknownBlockTypeDecodesAsUnsupportedInsteadOfFailing() throws {
        let blocks = try decodeBlocks(#"[{"type":"hologram","anything":1}]"#)
        XCTAssertEqual(blocks, [.unsupported(type: "hologram")])
    }

    func testKnownBlockMissingItsContentFailsToDecode() {
        XCTAssertThrowsError(try decodeBlocks(#"[{"type":"list"}]"#))
    }

    func testLessonVersionDefaultsToOneAndNotesToEmpty() throws {
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(BookFixtures.revolutions.utf8))
        XCTAssertEqual(lesson.version, 1)
        XCTAssertEqual(lesson.transcriptionNotes, [])
        XCTAssertEqual(lesson.terms.count, 0)
    }

    func testGlossaryIncludesDefinitionCardsThatHaveAnId() throws {
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(BookFixtures.empires.utf8))
        XCTAssertEqual(lesson.glossary["markets"]?.term, "Markets")
        XCTAssertEqual(lesson.glossary["markets"]?.definition, "Places where goods are traded.", "markup is removed from definitions")
    }

    func testBlockTextsListsEveryMarkupString() throws {
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(BookFixtures.rivers.utf8))
        let texts = lesson.pages[0].blocks.flatMap(\.texts)
        XCTAssertTrue(texts.contains("[[6650|e]]"))
        XCTAssertTrue(texts.contains("المصب"))
        XCTAssertTrue(texts.contains("النيل"))
    }
}

final class LessonValidatorTests: XCTestCase {
    private func lesson(pages: [LessonPage], terms: [String: TermDefinition] = [:]) -> Lesson {
        Lesson(id: "l", title: "T", terms: terms, pages: pages)
    }

    private func page(_ id: String = "p", blocks: [Block]) -> LessonPage {
        LessonPage(id: id, title: "Title", blocks: blocks)
    }

    func testAGoodLessonHasNoProblems() throws {
        let good = try JSONDecoder().decode(Lesson.self, from: Data(BookFixtures.empires.utf8))
        XCTAssertEqual(LessonValidator.problems(in: good), [])
    }

    func testDuplicatePageIdsAreReported() {
        let problems = LessonValidator.problems(in: lesson(pages: [page("a", blocks: [.paragraph("x")]), page("a", blocks: [.paragraph("y")])]))
        XCTAssertTrue(problems.contains { $0.contains("duplicate page id") })
    }

    func testSlashInAPageIdIsReported() {
        let problems = LessonValidator.problems(in: lesson(pages: [page("a/b", blocks: [.paragraph("x")])]))
        XCTAssertTrue(problems.contains { $0.contains("must not be empty or contain") })
    }

    func testUnknownTermIdIsReported() {
        let problems = LessonValidator.problems(in: lesson(pages: [page(blocks: [.paragraph("a {{b|nope}}")])]))
        XCTAssertTrue(problems.contains { $0.contains("unknown term id \"nope\"") })
    }

    func testTermFromTheGlossaryIsAccepted() {
        let terms = ["t": TermDefinition(term: "T", definition: "D")]
        XCTAssertEqual(LessonValidator.problems(in: lesson(pages: [page(blocks: [.paragraph("a {{b|t}}")])], terms: terms)), [])
    }

    func testMarkupProblemsAreReported() {
        let problems = LessonValidator.problems(in: lesson(pages: [page(blocks: [.paragraph("[[open")])]))
        XCTAssertTrue(problems.contains { $0.contains("unclosed") })
    }

    func testComparisonRowWithTheWrongNumberOfCellsIsReported() {
        let block = Block.comparison(title: nil, corner: nil, columns: ["a", "b"], rows: [ComparisonRow(label: "r", cells: ["only one"])])
        let problems = LessonValidator.problems(in: lesson(pages: [page(blocks: [block])]))
        XCTAssertTrue(problems.contains { $0.contains("1 cells for 2 columns") })
    }

    func testCauseEffectNeedsTwoStages() {
        let block = Block.causeEffect(title: nil, stages: [FlowStage(label: nil, nodes: ["a"])])
        XCTAssertTrue(LessonValidator.problems(in: lesson(pages: [page(blocks: [block])])).contains { $0.contains("two stages") })
    }

    func testImageNeedsAltText() {
        let block = Block.image(ImagePanel(name: "map", caption: nil, alt: "", style: nil))
        XCTAssertTrue(LessonValidator.problems(in: lesson(pages: [page(blocks: [block])])).contains { $0.contains("alt text") })
    }

    func testUnknownBlockTypeIsReported() {
        let problems = LessonValidator.problems(in: lesson(pages: [page(blocks: [.unsupported(type: "hologram")])]))
        XCTAssertTrue(problems.contains { $0.contains("hologram") })
    }

    func testEmptyLessonAndEmptyPageAreReported() {
        XCTAssertTrue(LessonValidator.problems(in: lesson(pages: [])).contains { $0.contains("no pages") })
        XCTAssertTrue(LessonValidator.problems(in: lesson(pages: [page(blocks: [])])).contains { $0.contains("no blocks") })
    }
}
