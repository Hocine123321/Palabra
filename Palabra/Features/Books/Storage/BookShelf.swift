import Foundation
import Observation

/// The Books tab's one dependency: the loaded books plus the person's reading state. Lives on `AppEnvironment` (`environment.books`).
@MainActor
@Observable
final class BookShelf {
    struct Progress: Equatable {
        var read: Int
        var total: Int

        var fraction: Double { total == 0 ? 0 : Double(read) / Double(total) }
    }

    private(set) var library: BookLibrary
    /// Changes whenever reading progress is cleared, so a 3D desk that is already loaded knows to start over.
    private(set) var resetToken = 0
    /// Changes whenever a lesson or chapter is saved, renamed or deleted. The 3D desk is built from the library when it
    /// appears, so it rebuilds when it comes back on screen with a newer version than the one it was built from.
    private(set) var libraryVersion = 0
    /// Set by Settings > Books > Pull a test; the 3D desk starts the recorded tour when it sees it.
    var tourRequested = false
    var state: TextbookState { didSet { store.value = state } }
    @ObservationIgnored private let store: TextbookStateStore
    @ObservationIgnored let source: BookContentSource

    init(source: BookContentSource = LessonStore.standard(), store: TextbookStateStore = TextbookStateStore()) {
        self.source = source
        self.store = store
        library = BookLibrary.load(from: source)
        state = store.value
    }

    /// Private state (nothing is saved to the real settings): the default for tests, previews and UI tests.
    /// With no `source`, lessons live in a private temporary store seeded from the bundle, so saving and editing work too.
    static func inMemory(source: BookContentSource? = nil) -> BookShelf {
        let defaults = UserDefaults(suiteName: "books-\(UUID().uuidString)") ?? .standard
        return BookShelf(source: source ?? LessonStore.temporary(seed: BundleBookSource()), store: TextbookStateStore(defaults: defaults))
    }

    func reload() {
        library = BookLibrary.load(from: source)
    }

    func book(id: String) -> Book? { library.book(id: id) }

    // MARK: Changing lessons (needs a `LessonStore` as the source)

    var lessonStore: LessonStore? { source as? LessonStore }

    /// The lesson as stored (the editable form), not the laid-out book pages.
    func lesson(id: String) -> Lesson? { lessonStore?.lesson(id: id) }

    func saveLesson(_ lesson: Lesson, bookID: String, chapterID: String) throws {
        try requireStore().save(lesson, bookID: bookID, chapterID: chapterID)
        libraryChanged()
    }

    func deleteLesson(id: String) throws {
        try requireStore().delete(lessonID: id)
        libraryChanged()
    }

    @discardableResult
    func addChapter(bookID: String, title: String) throws -> String {
        let id = try requireStore().addChapter(bookID: bookID, title: title)
        libraryChanged()
        return id
    }

    func renameChapter(bookID: String, chapterID: String, title: String) throws {
        try requireStore().renameChapter(bookID: bookID, chapterID: chapterID, title: title)
        libraryChanged()
    }

    private func requireStore() throws -> LessonStore {
        guard let store = lessonStore else { throw LessonStoreError.unknownBook }
        return store
    }

    private func libraryChanged() {
        reload()
        libraryVersion += 1
    }

    var preferences: ReaderPreferences {
        get { state.preferences }
        set { state.preferences = newValue }
    }

    func lastPageID(bookID: String) -> String? { state.progress[bookID]?.lastPageID }

    /// Pages opened so far, counting only pages the book still has.
    func progress(for book: Book) -> Progress {
        let visited = state.progress[book.id]?.visitedPageIDs ?? []
        let existing = Set(book.pages.map(\.id))
        return Progress(read: visited.intersection(existing).count, total: book.pages.count)
    }

    func progress(for lesson: BookLesson, in book: Book) -> Progress {
        let visited = state.progress[book.id]?.visitedPageIDs ?? []
        let read = lesson.pages.filter { visited.contains($0.id) }.count
        return Progress(read: read, total: lesson.pages.count)
    }

    func recordVisit(bookID: String, pageID: String) {
        var progress = state.progress[bookID] ?? BookProgress()
        progress.lastPageID = pageID
        progress.visitedPageIDs.insert(pageID)
        state.progress[bookID] = progress
    }

    func setBookmark(bookID: String, pageID: String?) {
        var progress = state.progress[bookID] ?? BookProgress()
        progress.bookmarkPageID = pageID
        state.progress[bookID] = progress
    }

    func bookmarkPageID(bookID: String) -> String? { state.progress[bookID]?.bookmarkPageID }

    func resetProgress(bookID: String) {
        state.progress[bookID] = nil
        resetToken += 1
    }
}
