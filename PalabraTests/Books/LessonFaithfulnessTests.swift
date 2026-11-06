import XCTest
@testable import Palabra

final class LessonFaithfulnessTests: XCTestCase {
    private func lesson(_ blocks: [Block], title: String = "Title", notes: [String] = []) -> Lesson {
        Lesson(id: "l", title: title, pages: [LessonPage(id: "p1", title: "Page", blocks: blocks)], transcriptionNotes: notes)
    }

    func testNumbersFromTheSourceAreAllowed() {
        let report = LessonFaithfulness.check(lesson([.paragraph("War in 1914 lasted until 1918")]), source: "War in 1914 lasted until 1918")
        XCTAssertEqual(report.blockedNumbers, [])
        XCTAssertTrue(report.isClean)
    }

    func testANewNumberIsBlocked() {
        let report = LessonFaithfulness.check(lesson([.paragraph("The date was 1954")]), source: "The date was 1945")
        XCTAssertEqual(report.blockedNumbers, ["1954"])
        XCTAssertFalse(report.isClean)
    }

    func testArabicIndicDigitsInTheSourceMatchWesternDigitsInTheOutput() {
        let report = LessonFaithfulness.check(lesson([.paragraph("سنة 1830")]), source: "سنة ١٨٣٠")
        XCTAssertEqual(report.blockedNumbers, [])
    }

    func testWesternDigitsInTheSourceMatchArabicIndicDigitsInTheOutput() {
        let report = LessonFaithfulness.check(lesson([.paragraph("سنة ١٨٣٠")]), source: "سنة 1830")
        XCTAssertEqual(report.blockedNumbers, [])
    }

    func testTranscriptionNotesAreNotChecked() {
        let report = LessonFaithfulness.check(lesson([.paragraph("text here")], notes: ["could not read 9999"]), source: "text here")
        XCTAssertEqual(report.blockedNumbers, [])
    }

    func testNewWordsAreWarningsOnly() {
        let report = LessonFaithfulness.check(lesson([.paragraph("Colonial trade")]), source: "trade")
        XCTAssertEqual(report.newWords, ["colonial"])
        XCTAssertTrue(report.isClean)
    }

    func testDiacriticsAndTheLeadingArticleDoNotCreateNewWords() {
        let report = LessonFaithfulness.check(lesson([.paragraph("الاستعمارُ الفرنسيّ")]), source: "استعمار فرنسي")
        XCTAssertEqual(report.newWords, [])
    }

    func testTermIDsAndRecallMarkersAreNotCounted() {
        let text = "{{الاستعمار|colonial-movement}} في [[1830|e]]"
        let report = LessonFaithfulness.check(lesson([.paragraph(text)]), source: "الاستعمار في 1830")
        XCTAssertEqual(report.newWords, [])
        XCTAssertEqual(report.blockedNumbers, [])
    }

    func testListNumberingIsNotChecked() {
        let report = LessonFaithfulness.check(lesson([.list(title: nil, items: ["first item", "second item"], ordered: true)]), source: "first item second item")
        XCTAssertEqual(report.blockedNumbers, [])
    }

    func testEveryBlockKindIsScanned() {
        let blocks: [Block] = [
            .timeline(title: nil, events: [TimelineEvent(date: "1999", title: "x", detail: nil)]),
            .stats(title: nil, items: [StatItem(label: "a", value: "42", unit: nil, note: nil)]),
        ]
        let report = LessonFaithfulness.check(lesson(blocks), source: "nothing here")
        XCTAssertEqual(Set(report.blockedNumbers), ["1999", "42"])
    }
}
