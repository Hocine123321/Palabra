import Foundation

enum LessonStoreError: Error, Equatable {
    case unknownBook, unknownChapter, unknownLesson
    /// A lesson or chapter id that is empty or could point outside the store.
    case invalidID
}

/// The writable home of every lesson the person reads, on the device: `catalogue.json` (books, chapters, lessons) and
/// one `lessons/<id>.json` per lesson, in the same formats as the bundled files (docs/features/books.md). It is a
/// `BookContentSource`, so `BookLibrary` loads it exactly like the bundle, and the 2D reader and the 3D desk read the same data.
///
/// The bundled lessons are copied in once (`seeded.json` remembers which), so they can be edited, and a lesson the person
/// deletes does not come back at the next launch. A lesson added to the app in an update is copied in the first time it is seen.
final class LessonStore: BookContentSource {
    let directory: URL
    private let fileManager = FileManager.default

    private var catalogueURL: URL { directory.appendingPathComponent("catalogue.json") }
    private var seededURL: URL { directory.appendingPathComponent("seeded.json") }
    private var lessonsDirectory: URL { directory.appendingPathComponent("lessons", isDirectory: true) }

    init(directory: URL, seed: BookContentSource?) {
        self.directory = directory
        try? fileManager.createDirectory(at: lessonsDirectory, withIntermediateDirectories: true)
        if let seed { seedIfNeeded(from: seed) }
    }

    /// The real store: Application Support/Books, seeded from the app bundle.
    static func standard() -> LessonStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LessonStore(directory: base.appendingPathComponent("Books", isDirectory: true), seed: BundleBookSource())
    }

    /// A private store in a fresh temporary folder: tests, previews and UI tests that must not touch the real one.
    static func temporary(seed: BookContentSource?) -> LessonStore {
        LessonStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("books-\(UUID().uuidString)", isDirectory: true), seed: seed)
    }

    // MARK: BookContentSource

    func catalogueData() throws -> Data {
        guard let data = try? Data(contentsOf: catalogueURL) else { throw BookLoadError.missingFile("catalogue") }
        return data
    }

    func lessonData(file: String) throws -> Data {
        guard !file.contains(".."), let data = try? Data(contentsOf: directory.appendingPathComponent(file + ".json")) else {
            throw BookLoadError.missingFile(file)
        }
        return data
    }

    // MARK: Reading

    func lesson(id: String) -> Lesson? {
        guard Self.isSafeID(id), let data = try? Data(contentsOf: lessonURL(id)) else { return nil }
        return try? LessonCoding.decode(data)
    }

    /// The book and chapter a lesson is listed under.
    func location(ofLesson id: String) -> (bookID: String, chapterID: String)? {
        guard let catalogue = readCatalogue() else { return nil }
        for book in catalogue.books {
            for chapter in book.chapters where chapter.lessons.contains(where: { $0.id == id }) {
                return (book.id, chapter.id)
            }
        }
        return nil
    }

    // MARK: Writing

    /// Writes the lesson. A lesson that already exists keeps its place in the catalogue; a new one is added at the end of the chapter.
    func save(_ lesson: Lesson, bookID: String, chapterID: String) throws {
        guard Self.isSafeID(lesson.id) else { throw LessonStoreError.invalidID }
        var catalogue = readCatalogue() ?? BookCatalogue(version: 1, books: [])
        let existing = location(ofLesson: lesson.id) != nil
        if !existing {
            guard let b = catalogue.books.firstIndex(where: { $0.id == bookID }) else { throw LessonStoreError.unknownBook }
            guard let c = catalogue.books[b].chapters.firstIndex(where: { $0.id == chapterID }) else { throw LessonStoreError.unknownChapter }
            catalogue.books[b].chapters[c].lessons.append(LessonRef(id: lesson.id, file: "lessons/\(lesson.id)"))
        }
        try LessonCoding.encode(lesson).write(to: lessonURL(lesson.id), options: .atomic)
        if !existing { try write(catalogue) }
    }

    func delete(lessonID: String) throws {
        guard Self.isSafeID(lessonID) else { throw LessonStoreError.invalidID }
        guard var catalogue = readCatalogue(), location(ofLesson: lessonID) != nil else { throw LessonStoreError.unknownLesson }
        for b in catalogue.books.indices {
            for c in catalogue.books[b].chapters.indices {
                catalogue.books[b].chapters[c].lessons.removeAll { $0.id == lessonID }
            }
        }
        try write(catalogue)
        try? fileManager.removeItem(at: lessonURL(lessonID))
    }

    /// Adds an empty chapter at the end of a book and returns its id.
    @discardableResult
    func addChapter(bookID: String, title: String) throws -> String {
        guard var catalogue = readCatalogue(), let b = catalogue.books.firstIndex(where: { $0.id == bookID }) else { throw LessonStoreError.unknownBook }
        let taken = Set(catalogue.books[b].chapters.map(\.id))
        var number = catalogue.books[b].chapters.count + 1
        while taken.contains("unit-\(number)") { number += 1 }
        let id = "unit-\(number)"
        catalogue.books[b].chapters.append(ChapterEntry(id: id, title: title, lessons: []))
        try write(catalogue)
        return id
    }

    func renameChapter(bookID: String, chapterID: String, title: String) throws {
        guard var catalogue = readCatalogue(), let b = catalogue.books.firstIndex(where: { $0.id == bookID }) else { throw LessonStoreError.unknownBook }
        guard let c = catalogue.books[b].chapters.firstIndex(where: { $0.id == chapterID }) else { throw LessonStoreError.unknownChapter }
        catalogue.books[b].chapters[c].title = title
        try write(catalogue)
    }

    // MARK: Seeding

    private func seedIfNeeded(from seed: BookContentSource) {
        guard let seedData = try? seed.catalogueData(), let seedCatalogue = try? JSONDecoder().decode(BookCatalogue.self, from: seedData) else { return }
        var catalogue = readCatalogue() ?? BookCatalogue(version: seedCatalogue.version ?? 1, books: [])
        var seeded = readSeeded()
        var changed = false
        for book in seedCatalogue.books {
            let b: Int
            if let found = catalogue.books.firstIndex(where: { $0.id == book.id }) {
                b = found
            } else {
                catalogue.books.append(BookEntry(id: book.id, subject: book.subject, title: book.title, language: book.language, chapters: []))
                b = catalogue.books.count - 1
                changed = true
            }
            for chapter in book.chapters {
                let c: Int
                if let found = catalogue.books[b].chapters.firstIndex(where: { $0.id == chapter.id }) {
                    c = found
                } else {
                    catalogue.books[b].chapters.append(ChapterEntry(id: chapter.id, title: chapter.title, lessons: []))
                    c = catalogue.books[b].chapters.count - 1
                    changed = true
                }
                for ref in chapter.lessons where !seeded.contains(ref.id) && Self.isSafeID(ref.id) {
                    guard let data = try? seed.lessonData(file: ref.file), location(in: catalogue, lesson: ref.id) == nil else { continue }
                    guard (try? data.write(to: lessonURL(ref.id), options: .atomic)) != nil else { continue }
                    catalogue.books[b].chapters[c].lessons.append(LessonRef(id: ref.id, file: "lessons/\(ref.id)"))
                    seeded.insert(ref.id)
                    changed = true
                }
            }
        }
        guard changed else { return }
        try? write(catalogue)
        try? JSONEncoder().encode(seeded.sorted()).write(to: seededURL, options: .atomic)
    }

    // MARK: Files

    private func lessonURL(_ id: String) -> URL { lessonsDirectory.appendingPathComponent(id + ".json") }

    private func readCatalogue() -> BookCatalogue? {
        guard let data = try? Data(contentsOf: catalogueURL) else { return nil }
        return try? JSONDecoder().decode(BookCatalogue.self, from: data)
    }

    private func readSeeded() -> Set<String> {
        guard let data = try? Data(contentsOf: seededURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    private func write(_ catalogue: BookCatalogue) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(catalogue).write(to: catalogueURL, options: .atomic)
    }

    private func location(in catalogue: BookCatalogue, lesson id: String) -> String? {
        for book in catalogue.books {
            for chapter in book.chapters where chapter.lessons.contains(where: { $0.id == id }) { return chapter.id }
        }
        return nil
    }

    /// Ids become file names: letters, digits, "-" and "_" only (no "/", no "..").
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }
}
