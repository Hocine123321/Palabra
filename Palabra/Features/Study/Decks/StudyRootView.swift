import SwiftUI

/// Top-level Study tab: its own navigation stack, independent of the Vocabulary `Router`.
struct StudyRootView: View {
    /// Passed in by the app so cards mirrored from library words can show pronunciation.
    var cardAccessory: (UUID) -> AnyView = { _ in AnyView(EmptyView()) }
    @State private var path: [StudyRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            StudyHomeView(path: $path)
                .navigationDestination(for: StudyRoute.self) { route in
                    switch route {
                    case .review(let deckID):
                        ReviewView(deckID: deckID, cardAccessory: cardAccessory)
                    case .deck(let id):
                        DeckDetailView(deckID: id, path: $path)
                    }
                }
        }
    }
}
