import Foundation

enum BookLoadError: Error, Equatable {
    case missingFile(String)
}

/// Where the catalogue and lesson files come from. The app reads its bundle; tests hand in strings.
protocol BookContentSource {
    func catalogueData() throws -> Data
    func lessonData(file: String) throws -> Data
}

final class BundleToken {}

/// Reads `textbooks.json` and the lesson files from the app bundle. Files may sit at the bundle root or in a "Books" folder.
struct BundleBookSource: BookContentSource {
    var bundle: Bundle = Bundle(for: BundleToken.self)

    func catalogueData() throws -> Data { try data(named: "textbooks") }

    func lessonData(file: String) throws -> Data { try data(named: file) }

    private func data(named name: String) throws -> Data {
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Books")
        guard let url else { throw BookLoadError.missingFile(name) }
        return try Data(contentsOf: url)
    }
}

/// Every book, resolved from the catalogue. A lesson that is missing or broken is left out and reported in `problems`;
/// it never takes the other lessons (or the app) down with it.
struct BookLibrary: Equatable {
    var books: [Book]
    /// Human-readable load and validation problems, for the developer. Empty when everything is fine.
    var problems: [String]

    static let empty = BookLibrary(books: [], problems: [])

    func book(id: String) -> Book? { books.first { $0.id == id } }

    static func load(from source: BookContentSource) -> BookLibrary {
        let decoder = JSONDecoder()
        let catalogue: BookCatalogue
        do {
            catalogue = try decoder.decode(BookCatalogue.self, from: try source.catalogueData())
        } catch {
            return BookLibrary(books: [], problems: ["catalogue: \(error)"])
        }

        var problems: [String] = []
        var books: [Book] = []
        var seenBooks = Set<String>()
        for entry in catalogue.books {
            guard seenBooks.insert(entry.id).inserted else {
                problems.append("duplicate book id \(entry.id)")
                continue
            }
            var number = 0
            var allPages: [BookPage] = []
            var chapters: [BookChapter] = []
            var seenLessons = Set<String>()
            for chapterEntry in entry.chapters {
                var lessons: [BookLesson] = []
                for ref in chapterEntry.lessons {
                    let label = "\(entry.id)/\(ref.id)"
                    guard !ref.id.isEmpty, !ref.id.contains("/"), seenLessons.insert(ref.id).inserted else {
                        problems.append("\(label): lesson id is empty, contains \"/\" or is used twice")
                        continue
                    }
                    let lesson: Lesson
                    do {
                        lesson = try decoder.decode(Lesson.self, from: try source.lessonData(file: ref.file))
                    } catch {
                        problems.append("\(label): \(error)")
                        continue
                    }
                    if lesson.id != ref.id { problems.append("\(label): the lesson file says id \"\(lesson.id)\"") }
                    problems += LessonValidator.problems(in: lesson).map { "\(label): \($0)" }

                    let glossary = lesson.glossary
                    var pages: [BookPage] = []
                    var seenPages = Set<String>()
                    for page in lesson.pages {
                        if !seenPages.insert(page.id).inserted { continue }
                        number += 1
                        pages.append(BookPage(
                            id: "\(ref.id)/\(page.id)",
                            number: number,
                            chapterID: chapterEntry.id,
                            lessonID: ref.id,
                            lessonTitle: lesson.title,
                            page: page,
                            glossary: glossary
                        ))
                    }
                    allPages += pages
                    lessons.append(BookLesson(
                        id: ref.id,
                        chapterID: chapterEntry.id,
                        title: lesson.title,
                        summary: lesson.summary,
                        version: lesson.version,
                        notes: lesson.transcriptionNotes,
                        pages: pages
                    ))
                }
                chapters.append(BookChapter(id: chapterEntry.id, title: chapterEntry.title, lessons: lessons))
            }
            books.append(Book(
                id: entry.id,
                subject: entry.subject,
                title: entry.title,
                language: entry.language,
                chapters: chapters,
                pages: allPages
            ))
        }
        return BookLibrary(books: books, problems: problems)
    }
}
