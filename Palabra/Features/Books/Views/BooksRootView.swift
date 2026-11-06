import SwiftUI

enum BooksRoute: Hashable {
    case book(String)
    /// `pageID` is a `lesson/page` id; nil resumes where the person stopped.
    case reader(bookID: String, pageID: String?)
}

/// The Books tab: its own navigation stack, independent of the Spanish `Router`. The root is the 3D desk. The text reader and
/// the lesson list stay behind "Read as text" on the desk (they are also what VoiceOver users read).
struct BooksRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [BooksRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            BooksSceneScreen(path: $path)
                .id(environment.books.resetToken)
            .navigationDestination(for: BooksRoute.self) { route in
                    switch route {
                    case .book(let id):
                        BookDetailView(bookID: id)
                    case .reader(let bookID, let pageID):
                        BookReaderView(bookID: bookID, startPageID: pageID)
                    }
                }
        }
    }
}
