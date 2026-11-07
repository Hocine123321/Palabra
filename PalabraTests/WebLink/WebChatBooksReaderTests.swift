import XCTest
@testable import Palabra

final class WebChatBooksReaderTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func reader(chat: WebChatBooksReader.Chat? = nil, books: [WebChatBooksReader.BookEntry] = [], lesson: WebChatBooksReader.Lesson? = nil) -> WebChatBooksReader {
        WebChatBooksReader(latestChat: { chat }, books: { books }, lesson: { _, id in lesson?.id == id ? lesson : nil })
    }

    private func turn(_ role: String, _ text: String, actions: Int = 0, failed: Bool = false) -> WebChatBooksReader.Turn {
        .init(role: role, text: text, at: when, actionCount: actions, failed: failed)
    }

    func testNoChatAnswersAnExplicitNull() async {
        let payload = await reader().chatPayload()
        XCTAssertEqual(payload, .object(["chat": .null]))
    }

    func testAChatIsSentAsTextWithOnlyACountOfWhatTheToolsDid() async {
        let chat = WebChatBooksReader.Chat(id: "c1", title: "Verbos", updatedAt: when, turns: [turn("user", "hola"), turn("assistant", "¡Hola!", actions: 2)])
        let payload = await reader(chat: chat).chatPayload()
        guard case .object(let top) = payload, case .object(let c)? = top["chat"], case .array(let turns)? = c["turns"] else { return XCTFail("shape") }
        XCTAssertEqual(c["title"]?.stringValue, "Verbos")
        XCTAssertEqual(turns.count, 2)
        guard case .object(let second) = turns[1] else { return XCTFail("turn") }
        XCTAssertEqual(second["actions"], .number(2))
        XCTAssertNil(second["thumbnail"])
        XCTAssertNil(second["argsJSON"])
    }

    func testLongChatsAndLongTurnsAreCut() async {
        let many = (0..<(WebChatBooksReader.maxTurns + 25)).map { turn("user", "n\($0)") }
        let long = turn("assistant", String(repeating: "a", count: WebChatBooksReader.maxTurnText + 500))
        let payload = await reader(chat: .init(id: "c", title: "t", updatedAt: when, turns: many + [long])).chatPayload()
        guard case .object(let top) = payload, case .object(let c)? = top["chat"], case .array(let turns)? = c["turns"], case .object(let last)? = turns.last else { return XCTFail("shape") }
        XCTAssertEqual(turns.count, WebChatBooksReader.maxTurns)
        XCTAssertEqual(last["text"]?.stringValue?.count, WebChatBooksReader.maxTurnText)
    }

    func testBooksAreListedWithChaptersAndLessons() async {
        let book = WebChatBooksReader.BookEntry(id: "b1", title: "Historia", subject: "history", language: "es",
            chapters: [.init(id: "ch1", title: "Uno", lessons: [.init(id: "l1", title: "Roma")])])
        let payload = await reader(books: [book]).booksPayload()
        guard case .array(let list) = payload, case .object(let first)? = list.first, case .array(let chapters)? = first["chapters"],
              case .object(let chapter)? = chapters.first, case .array(let lessons)? = chapter["lessons"], case .object(let lesson)? = lessons.first else { return XCTFail("shape") }
        XCTAssertEqual(first["title"]?.stringValue, "Historia")
        XCTAssertEqual(lesson["title"]?.stringValue, "Roma")
    }

    func testTextBlocksBecomeTextAndVisualBlocksBecomeAnHonestNote() {
        XCTAssertEqual(WebChatBooksReader.piece(from: .paragraph("Hola {{mundo|m}}")).kind, "text")
        XCTAssertEqual(WebChatBooksReader.piece(from: .heading(text: "Titulo", level: 9)).level, 3)
        let list = WebChatBooksReader.piece(from: .list(title: nil, items: ["a", "b"], ordered: true))
        XCTAssertEqual(list.items, ["a", "b"])
        XCTAssertTrue(list.ordered)
        let timeline = WebChatBooksReader.piece(from: .timeline(title: nil, events: [TimelineEvent(date: "1", title: "x", detail: nil)]))
        XCTAssertEqual(timeline.kind, "note")
        XCTAssertEqual(WebChatBooksReader.piece(from: .unsupported(type: "future")).kind, "note")
    }

    func testALessonIsSentAndAnUnknownOneIsNot() async {
        let lesson = WebChatBooksReader.Lesson(id: "l1", title: "Roma", pages: [.init(id: "p1", title: "Roma", blocks: [WebChatBooksReader.piece(from: .paragraph("Texto"))])])
        let r = reader(lesson: lesson)
        let found = await r.lessonPayload(bookID: "b1", lessonID: "l1")
        let missing = await r.lessonPayload(bookID: "b1", lessonID: "nope")
        XCTAssertNotNil(found)
        XCTAssertNil(missing)
    }

    func testTheDispatcherAnswersChatBooksAndLessonsAndRefusesBadRequests() async {
        let lesson = WebChatBooksReader.Lesson(id: "l1", title: "Roma", pages: [])
        let d = WebLinkDispatcher(registry: CapabilityRegistry([]), chatBooks: reader(lesson: lesson))
        let chat = await d.handle(LinkMessage(id: "1", type: "chat", version: 1, payload: nil))
        let books = await d.handle(LinkMessage(id: "2", type: "books", version: 1, payload: nil))
        let good = await d.handle(LinkMessage(id: "3", type: "lesson", version: 1, payload: .object(["book": .string("b1"), "lesson": .string("l1")])))
        let missing = await d.handle(LinkMessage(id: "4", type: "lesson", version: 1, payload: .object(["book": .string("b1"), "lesson": .string("zz")])))
        let bad = await d.handle(LinkMessage(id: "5", type: "lesson", version: 1, payload: .object(["book": .number(1)])))
        XCTAssertEqual(chat?.type, "ack")
        XCTAssertEqual(books?.type, "ack")
        XCTAssertEqual(good?.type, "ack")
        XCTAssertEqual(missing?.payload, .object(["reason": .string("not-found")]))
        XCTAssertEqual(bad?.payload, .object(["reason": .string("bad-request")]))
    }

    func testWithoutAReaderThePageSeesNothingRatherThanAnError() async {
        let d = WebLinkDispatcher(registry: CapabilityRegistry([]))
        let chat = await d.handle(LinkMessage(id: "1", type: "chat", version: 1, payload: nil))
        let books = await d.handle(LinkMessage(id: "2", type: "books", version: 1, payload: nil))
        XCTAssertEqual(chat?.payload, .object(["result": .object(["chat": .null])]))
        XCTAssertEqual(books?.payload, .object(["result": .array([])]))
    }
}
