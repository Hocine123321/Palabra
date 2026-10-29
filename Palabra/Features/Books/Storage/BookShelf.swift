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
    var state: TextbookState { didSet { store.value = state } }
    @ObservationIgnored private let store: TextbookStateStore
    @ObservationIgnored private let source: BookContentSource

    init(source: BookContentSource = BundleBookSource(), store: TextbookStateStore = TextbookStateStore()) {
        self.source = source
        self.store = store
        library = BookLibrary.load(from: source)
        state = store.value
    }

    /// Private state (nothing is saved to the real settings): the default for tests, previews and UI tests.
    static func inMemory(source: BookContentSource = BundleBookSource()) -> BookShelf {
        let defaults = UserDefaults(suiteName: "books-\(UUID().uuidString)") ?? .standard
        return BookShelf(source: source, store: TextbookStateStore(defaults: defaults))
    }

    func reload() {
        library = BookLibrary.load(from: source)
    }

    func book(id: String) -> Book? { library.book(id: id) }

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

    func resetProgress(bookID: String) {
        state.progress[bookID] = nil
    }
}
