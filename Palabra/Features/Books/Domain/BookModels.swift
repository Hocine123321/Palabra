import Foundation

enum BookSubject: String, Decodable, CaseIterable, Sendable {
    case history
    case geography
}

// MARK: - The catalogue file (Resources/Books/textbooks.json)

struct BookCatalogue: Decodable, Equatable {
    var version: Int?
    var books: [BookEntry]
}

struct BookEntry: Decodable, Equatable, Identifiable {
    var id: String
    var subject: BookSubject
    var title: String
    /// Language of the lessons ("ar", "en", ...). Decides the reading direction of the whole book.
    var language: String
    var chapters: [ChapterEntry]
}

struct ChapterEntry: Decodable, Equatable, Identifiable {
    var id: String
    var title: String
    var lessons: [LessonRef]
}

struct LessonRef: Decodable, Equatable, Identifiable {
    /// Stable id, used in saved reading positions. Never contains "/".
    var id: String
    /// Name of the lesson's JSON file in the bundle, without ".json".
    var file: String
}

// MARK: - What the app works with once everything is loaded

struct BookPage: Identifiable, Equatable {
    /// `<lesson id>/<page id>`: unique in the book and what reading progress is saved under.
    let id: String
    /// 1-based position in the whole book.
    let number: Int
    let chapterID: String
    let lessonID: String
    let lessonTitle: String
    let page: LessonPage
    let glossary: [String: TermDefinition]
}

struct BookLesson: Identifiable, Equatable {
    let id: String
    let chapterID: String
    let title: String
    let summary: String?
    let version: Int
    let notes: [String]
    let pages: [BookPage]
}

struct BookChapter: Identifiable, Equatable {
    let id: String
    let title: String
    let lessons: [BookLesson]
}

struct Book: Identifiable, Equatable {
    let id: String
    let subject: BookSubject
    let title: String
    let language: String
    let chapters: [BookChapter]
    /// Every page of every lesson, in reading order.
    let pages: [BookPage]

    var isEmpty: Bool { pages.isEmpty }

    var lessonCount: Int { chapters.reduce(0) { $0 + $1.lessons.count } }

    var isRightToLeft: Bool { Locale.characterDirection(forLanguage: language) == .rightToLeft }

    func index(ofPage id: String) -> Int? { pages.firstIndex { $0.id == id } }

    func firstPageIndex(ofLesson lessonID: String) -> Int? { pages.firstIndex { $0.lessonID == lessonID } }

    /// Where to open the book: the saved page; when that page no longer exists (the lesson was rewritten), the start of
    /// its lesson; when the whole lesson is gone, the first page.
    func resumeIndex(lastPageID: String?) -> Int {
        guard let lastPageID else { return 0 }
        if let exact = index(ofPage: lastPageID) { return exact }
        if let slash = lastPageID.firstIndex(of: "/") {
            let lessonID = String(lastPageID[..<slash])
            if let start = firstPageIndex(ofLesson: lessonID) { return start }
        }
        return 0
    }
}
