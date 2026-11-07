import XCTest
@testable import Palabra

final class LessonEditorTests: XCTestCase {
    private func lesson() -> Lesson {
        Lesson(id: "l", title: "Lesson", pages: [
            LessonPage(id: "intro", title: "Intro", blocks: [.paragraph("one"), .paragraph("two"), .paragraph("three")]),
            LessonPage(id: "p2", title: "Second", blocks: [.paragraph("only")]),
        ])
    }

    private func texts(_ lesson: Lesson, _ page: String) -> [String] {
        lesson.pages.first { $0.id == page }!.blocks.map { block -> String in
            if case .paragraph(let text) = block { return text }
            return "?"
        }
    }

    func testBlockOperationsKeepPageIDsAndOtherBlocks() {
        var result = LessonEditor.replaceBlock(lesson(), pageID: "intro", index: 1, with: .paragraph("TWO"))
        XCTAssertEqual(texts(result, "intro"), ["one", "TWO", "three"])
        result = LessonEditor.insertBlock(result, pageID: "intro", at: 0, block: .paragraph("zero"))
        XCTAssertEqual(texts(result, "intro"), ["zero", "one", "TWO", "three"])
        result = LessonEditor.moveBlock(result, pageID: "intro", from: 0, to: 3)
        XCTAssertEqual(texts(result, "intro"), ["one", "TWO", "three", "zero"])
        result = LessonEditor.deleteBlock(result, pageID: "intro", index: 1)
        XCTAssertEqual(texts(result, "intro"), ["one", "three", "zero"])
        XCTAssertEqual(result.pages.map(\.id), ["intro", "p2"])
        XCTAssertEqual(LessonValidator.problems(in: result), [])
    }

    func testTheLastBlockOfAPageCannotBeDeleted() {
        let start = lesson()
        XCTAssertEqual(LessonEditor.deleteBlock(start, pageID: "p2", index: 0), start)
    }

    func testTheLastPageOfALessonCannotBeDeleted() {
        let one = Lesson(id: "l", title: "L", pages: [LessonPage(id: "a", title: "A", blocks: [.paragraph("x")])])
        XCTAssertEqual(LessonEditor.deletePage(one, pageID: "a"), one)
        XCTAssertEqual(LessonEditor.deletePage(lesson(), pageID: "intro").pages.map(\.id), ["p2"])
    }

    func testOutOfRangeEditsChangeNothing() {
        let start = lesson()
        XCTAssertEqual(LessonEditor.replaceBlock(start, pageID: "intro", index: 9, with: .paragraph("x")), start)
        XCTAssertEqual(LessonEditor.moveBlock(start, pageID: "intro", from: 0, to: 9), start)
        XCTAssertEqual(LessonEditor.deleteBlock(start, pageID: "missing", index: 0), start)
        XCTAssertEqual(LessonEditor.movePage(start, pageID: "intro", by: -1), start)
    }

    func testAddPageGetsAFreshValidIDAndPlacement() {
        var result = LessonEditor.deletePage(lesson(), pageID: "p2") // ids used so far: intro, p2
        let added = LessonEditor.addPage(result, after: "intro", title: "New page")
        result = added.lesson
        XCTAssertEqual(added.pageID, "p1")
        XCTAssertFalse(added.pageID.contains("/"))
        XCTAssertEqual(result.pages.map(\.id), ["intro", "p1"])
        let again = LessonEditor.addPage(result, after: nil, title: "")
        XCTAssertEqual(again.lesson.pages.map(\.id), ["intro", "p1", "p2"])
        XCTAssertEqual(LessonValidator.problems(in: again.lesson), [])
    }

    func testTitlesAndDateLabels() {
        var result = LessonEditor.setPageTitle(lesson(), pageID: "intro", title: "  New  ")
        XCTAssertEqual(result.pages[0].title, "New")
        XCTAssertEqual(LessonEditor.setPageTitle(result, pageID: "intro", title: "  "), result)
        result = LessonEditor.setDateLabel(result, pageID: "intro", label: "1830")
        XCTAssertEqual(result.pages[0].dateLabel, "1830")
        XCTAssertNil(LessonEditor.setDateLabel(result, pageID: "intro", label: " ").pages[0].dateLabel)
        XCTAssertEqual(LessonEditor.renameLesson(result, title: "Renamed").title, "Renamed")
        XCTAssertEqual(LessonEditor.renameLesson(result, title: ""), result)
    }

    func testMovePage() {
        XCTAssertEqual(LessonEditor.movePage(lesson(), pageID: "intro", by: 1).pages.map(\.id), ["p2", "intro"])
    }
}

final class BlockDraftTests: XCTestCase {
    func testEveryEditableBlockRoundTripsThroughItsDraft() throws {
        let blocks: [Block] = [
            .heading(text: "H", level: 3),
            .paragraph("P"),
            .list(title: "T", items: ["a", "b"], ordered: true),
            .keyPoint(label: "L", text: "K"),
            .quote(text: "Q", source: "S"),
            .timeline(title: "T", events: [TimelineEvent(date: "1830", title: "E", detail: "D")]),
            .stats(title: "T", items: [StatItem(label: "a", value: "1", unit: "km", note: "n")]),
            .comparison(title: "T", corner: "C", columns: ["A", "B"], rows: [ComparisonRow(label: "r", cells: ["1", "2"])]),
            .causeEffect(title: "T", stages: [FlowStage(label: "L", nodes: ["x"]), FlowStage(label: nil, nodes: ["y"])]),
            .process(title: "T", steps: [ProcessStep(title: "s", detail: "d")]),
            .definitions(title: "T", items: [DefinitionItem(id: "t1", term: "t", definition: "d")]),
        ]
        for block in blocks {
            let draft = try XCTUnwrap(BlockDraft(block))
            XCTAssertEqual(draft.block(), block)
        }
    }

    func testImagesAndUnknownBlocksHaveNoForm() {
        XCTAssertNil(BlockDraft(.image(ImagePanel(name: "x", caption: nil, alt: "a", style: nil))))
        XCTAssertNil(BlockDraft(.unsupported(type: "hologram")))
    }

    func testBlankDraftsAreNotBlocksAndBlankRowsAreDropped() {
        for kind in BlockDraft.Kind.allCases { XCTAssertNil(BlockDraft(kind: kind).block(), "\(kind) blank") }
        var list = BlockDraft(kind: .list)
        list.items = ["a", "  ", "b"]
        XCTAssertEqual(list.block(), .list(title: nil, items: ["a", "b"], ordered: false))
    }

    func testComparisonRowsAreKeptTheSizeOfTheColumns() {
        var draft = BlockDraft(kind: .comparison)
        draft.columns = ["A", "B", "C"]
        draft.rows = [ComparisonRow(label: "r", cells: ["1"])]
        XCTAssertEqual(draft.block(), .comparison(title: nil, corner: nil, columns: ["A", "B", "C"], rows: [ComparisonRow(label: "r", cells: ["1", "", ""])]))
    }
}
