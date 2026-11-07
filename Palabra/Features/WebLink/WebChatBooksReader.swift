import Foundation

/// What the web page may know about the person's latest chat and their textbooks. Read-only, plain values only.
///
/// - Chat: the most recent conversation as text. Photos, thumbnails, tool-call arguments and results are never sent; a turn
///   that used the phone's tools only says how many actions it ran. Long text is cut (the page shows what the phone keeps anyway).
/// - Books: the catalogue (books, chapters, lessons) and, for one lesson, its pages as text. Blocks that are mostly visual
///   (timelines, diagrams, comparisons, images) are sent as a short note that points back to the phone, never guessed at.
struct WebChatBooksReader: Sendable {
    struct Turn: Sendable, Equatable {
        let role: String          // "user" | "assistant"
        let text: String
        let at: Date
        let actionCount: Int
        let failed: Bool
    }
    struct Chat: Sendable, Equatable {
        let id: String
        let title: String
        let updatedAt: Date
        let turns: [Turn]
    }
    struct Lesson: Sendable, Equatable {
        let id: String
        let title: String
        let pages: [Page]
    }
    struct Page: Sendable, Equatable {
        let id: String
        let title: String
        let blocks: [Piece]
    }
    /// A lesson block already reduced to text. `kind` is what the page styles; `visual` means "see it on the phone".
    struct Piece: Sendable, Equatable {
        let kind: String          // heading | text | list | keyPoint | quote | definitions | note
        let text: String
        let items: [String]
        let ordered: Bool
        let level: Int
    }
    struct BookEntry: Sendable, Equatable {
        struct Chapter: Sendable, Equatable { let id: String; let title: String; let lessons: [LessonRef] }
        struct LessonRef: Sendable, Equatable { let id: String; let title: String }
        let id: String
        let title: String
        let subject: String
        let language: String
        let chapters: [Chapter]
    }

    static let maxTurns = 60
    static let maxTurnText = 4_000
    static let maxPages = 60
    static let maxBlocks = 80

    let latestChat: @Sendable () async -> Chat?
    let books: @Sendable () async -> [BookEntry]
    let lesson: @Sendable (_ bookID: String, _ lessonID: String) async -> Lesson?

    func chatPayload() async -> JSONValue {
        guard let chat = await latestChat() else { return .object(["chat": .null]) }
        let iso = ISO8601DateFormatter()
        let turns = chat.turns.suffix(Self.maxTurns).map { turn -> JSONValue in
            .object([
                "role": .string(turn.role),
                "text": .string(String(turn.text.prefix(Self.maxTurnText))),
                "at": .string(iso.string(from: turn.at)),
                "actions": .number(Double(turn.actionCount)),
                "failed": .bool(turn.failed),
            ])
        }
        return .object(["chat": .object([
            "id": .string(chat.id), "title": .string(chat.title),
            "updatedAt": .string(iso.string(from: chat.updatedAt)),
            "turns": .array(Array(turns)),
        ])])
    }

    func booksPayload() async -> JSONValue {
        let list = await books().prefix(50).map { book -> JSONValue in
            .object([
                "id": .string(book.id), "title": .string(book.title), "subject": .string(book.subject), "language": .string(book.language),
                "chapters": .array(book.chapters.prefix(100).map { chapter in
                    .object(["id": .string(chapter.id), "title": .string(chapter.title),
                             "lessons": .array(chapter.lessons.prefix(100).map { .object(["id": .string($0.id), "title": .string($0.title)]) })])
                }),
            ])
        }
        return .array(Array(list))
    }

    /// `nil` = no such lesson.
    func lessonPayload(bookID: String, lessonID: String) async -> JSONValue? {
        guard let lesson = await lesson(bookID, lessonID) else { return nil }
        let pages = lesson.pages.prefix(Self.maxPages).map { page -> JSONValue in
            .object(["id": .string(page.id), "title": .string(page.title),
                     "blocks": .array(page.blocks.prefix(Self.maxBlocks).map { block in
                        .object(["kind": .string(block.kind), "text": .string(String(block.text.prefix(Self.maxTurnText))),
                                 "items": .array(block.items.prefix(100).map { .string(String($0.prefix(600))) }),
                                 "ordered": .bool(block.ordered), "level": .number(Double(block.level))])
                     })])
        }
        return .object(["id": .string(lesson.id), "title": .string(lesson.title), "pages": .array(Array(pages))])
    }

    /// Reduces a lesson block to text. Anything whose meaning is in its layout becomes a note, not a guess.
    static func piece(from block: Block) -> Piece {
        func plain(_ text: String) -> String { InlineMarkup.plainText(text) }
        let note = Piece(kind: "note", text: "This part is best read on the phone.", items: [], ordered: false, level: 0)
        switch block {
        case .heading(let text, let level):
            return Piece(kind: "heading", text: plain(text), items: [], ordered: false, level: min(max(level, 1), 3))
        case .paragraph(let text):
            return Piece(kind: "text", text: plain(text), items: [], ordered: false, level: 0)
        case .list(let title, let items, let ordered):
            return Piece(kind: "list", text: plain(title ?? ""), items: items.map(plain), ordered: ordered, level: 0)
        case .keyPoint(let label, let text):
            return Piece(kind: "keyPoint", text: plain(text), items: label.map { [plain($0)] } ?? [], ordered: false, level: 0)
        case .quote(let text, let source):
            return Piece(kind: "quote", text: plain(text), items: source.map { [plain($0)] } ?? [], ordered: false, level: 0)
        case .definitions(let title, let items):
            return Piece(kind: "definitions", text: plain(title ?? ""), items: items.map { "\(plain($0.term)): \(plain($0.definition))" }, ordered: false, level: 0)
        default:
            return note
        }
    }
}
