import Foundation

/// Books lessons as mirror records, one item per lesson and one per page, so every item stays far below the Worker's
/// per-item cap. Like the other `AppEnvironment+Mirror*` files, this is where the Books types become plain JSON.
extension AppEnvironment {
    /// Collections `lesson` and `lessonPage`. Always built: a deleted lesson drops out of the next build, so the pusher
    /// tombstones its records.
    func mirrorBooksCollections() -> [MirrorCollection] {
        var lessons: [MirrorRecord] = []
        var pages: [MirrorRecord] = []
        for book in books.library.books {
            let chapterTitles = Dictionary(book.chapters.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            for lesson in book.chapters.flatMap(\.lessons) {
                let terms = (try? JSONEncoder().encode(lesson.pages.first?.glossary ?? [:])).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])
                let summary: JSONValue = lesson.summary.map { JSONValue.string($0) } ?? .null
                let pageIDs: [JSONValue] = lesson.pages.map { JSONValue.string($0.page.id) }
                let notes: [JSONValue] = lesson.notes.map { JSONValue.string($0) }
                let lessonPayload: JSONValue = .object([
                    "id": .string(lesson.id),
                    "version": .number(Double(lesson.version)),
                    "title": .string(lesson.title),
                    "summary": summary,
                    "bookId": .string(book.id),
                    "bookTitle": .string(book.title),
                    "chapterId": .string(lesson.chapterID),
                    "chapterTitle": .string(chapterTitles[lesson.chapterID] ?? ""),
                    "language": .string(book.language),
                    "pageIds": .array(pageIDs),
                    "terms": terms,
                    "notes": .array(notes),
                ])
                lessons.append(MirrorRecord(kind: "lesson", recordID: lesson.id, payload: lessonPayload))

                for page in lesson.pages {
                    let pagePayload: JSONValue = .object([
                        "lessonId": .string(lesson.id),
                        "id": .string(page.page.id),
                        "number": .number(Double(page.number)),
                        "title": .string(page.page.title),
                        "dateLabel": page.page.dateLabel.map { JSONValue.string($0) } ?? .null,
                        "blocks": Self.mirrorBlocks(page.page.blocks),
                    ])
                    pages.append(MirrorRecord(kind: "lessonPage", recordID: page.id, payload: pagePayload))
                }
            }
        }
        return [MirrorCollection(kind: "lesson", records: lessons), MirrorCollection(kind: "lessonPage", records: pages)]
    }

    /// The blocks in the JSON shape the lesson files use (the existing `Codable` encoding), except that an image is
    /// reduced to its `alt` and `caption`: its asset name is no use outside the phone and no picture is ever sent.
    static func mirrorBlocks(_ blocks: [Block]) -> JSONValue {
        let encoded: [JSONValue] = blocks.map { block in
            let json = (try? JSONEncoder().encode(block)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
                ?? .object(["type": .string("unsupported")])
            guard case .image(let panel) = block else { return json }
            var object: [String: JSONValue] = ["type": .string("image"), "alt": .string(panel.alt)]
            if let caption = panel.caption { object["caption"] = .string(caption) }
            return .object(object)
        }
        return .array(encoded)
    }
}
