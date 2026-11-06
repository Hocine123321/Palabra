import XCTest
@testable import Palabra

final class LessonCodingTests: XCTestCase {
    private func sampleLesson() -> Lesson {
        let blocks: [Block] = [
            .heading(text: "Heading", level: 3),
            .paragraph("Paragraph with {{term|t1}} and [[1954|e]] and **bold**"),
            .list(title: "List", items: ["a", "b"], ordered: true),
            .keyPoint(label: "Note", text: "Key"),
            .quote(text: "Quote", source: "Source"),
            .timeline(title: "Timeline", events: [TimelineEvent(date: "1830", title: "Event", detail: "Detail")]),
            .stats(title: "Stats", items: [StatItem(label: "L", value: "5", unit: "km", note: "n")]),
            .comparison(title: "Cmp", corner: "Corner", columns: ["A", "B"], rows: [ComparisonRow(label: "r", cells: ["1", "2"])]),
            .causeEffect(title: "CE", stages: [FlowStage(label: "Causes", nodes: ["x"]), FlowStage(label: nil, nodes: ["y"])]),
            .process(title: "Proc", steps: [ProcessStep(title: "Step", detail: "d")]),
            .definitions(title: "Defs", items: [DefinitionItem(id: "t1", term: "Term", definition: "Meaning")]),
            .image(ImagePanel(name: "map1", caption: "Cap", alt: "Alt", style: "map")),
        ]
        return Lesson(
            id: "sample", version: 2, title: "Sample", summary: "Sum",
            terms: ["t1": TermDefinition(term: "Term", definition: "Meaning")],
            pages: [LessonPage(id: "p1", title: "Page", dateLabel: "1830", blocks: blocks)],
            transcriptionNotes: ["unclear word"]
        )
    }

    func testEveryBlockTypeRoundTrips() throws {
        let lesson = sampleLesson()
        let decoded = try LessonCoding.decode(try LessonCoding.encode(lesson))
        XCTAssertEqual(decoded, lesson)
    }

    func testTheBundledLessonRoundTrips() throws {
        let data = try BundleBookSource().lessonData(file: "lesson-history-colonial-movement")
        let lesson = try LessonCoding.decode(data)
        XCTAssertEqual(try LessonCoding.decode(try LessonCoding.encode(lesson)), lesson)
    }

    func testEncodedBlockKeysMatchTheDocumentedFormat() throws {
        let text = String(decoding: try LessonCoding.encode(sampleLesson()), as: UTF8.self)
        for expected in [#""type" : "timeline""#, #""events""#, #""stats""#, #""definitions""#, #""image" : "map1""#, #""type" : "causeEffect""#, #""corner" : "Corner""#] {
            XCTAssertTrue(text.contains(expected), "missing \(expected)")
        }
        XCTAssertFalse(text.contains(#""name""#), "an image block must use the key image, not name")
    }

    func testUnsupportedBlockEncodesItsType() throws {
        let lesson = Lesson(id: "u", title: "U", pages: [LessonPage(id: "p", title: "P", blocks: [.unsupported(type: "hologram")])])
        let text = String(decoding: try LessonCoding.encode(lesson), as: UTF8.self)
        XCTAssertTrue(text.contains(#""type" : "hologram""#))
        XCTAssertEqual(try LessonCoding.decode(try LessonCoding.encode(lesson)), lesson)
    }
}
