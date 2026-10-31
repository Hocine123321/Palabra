import SwiftUI

enum BooksRoute: Hashable {
    case book(String)
    /// `pageID` is a `lesson/page` id; nil resumes where the person stopped.
    case reader(bookID: String, pageID: String?)
}

/// The Books tab: its own navigation stack, independent of the Spanish `Router`. The root is the 3D desk by default; the
/// classic flat shelf is an option in Settings (and is what shows if the 3D view can't start). The text reader and the
/// lesson list stay behind "Read as text" on the desk.
struct BooksRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [BooksRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch environment.books.preferences.viewStyle {
                case .desk:
                    BooksSceneScreen(path: $path)
                        .id(environment.books.resetToken)
                case .classic:
                    BookshelfView()
                }
            }
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
