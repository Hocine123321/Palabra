import SwiftUI

/// Top-level Study tab: its own navigation stack, independent of the Vocabulary `Router`.
struct StudyRootView: View {
    /// Passed in by the app so cards mirrored from library words can show pronunciation.
    var cardAccessory: (UUID) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Passed in by the app: a tint for a card's front (a colour word gets its colour), nil for the deck's own tint.
    var cardTint: (String) -> Color? = { _ in nil }
    @State private var path: [StudyRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            StudyHomeView(path: $path)
                .navigationDestination(for: StudyRoute.self) { route in
                    switch route {
                    case .review(let deckID):
                        ReviewView(deckID: deckID, cardAccessory: cardAccessory, cardTint: cardTint)
                    case .deck(let id):
                        DeckDetailView(deckID: id, path: $path)
                    case .examSetup:
                        ExamSetupView(path: $path)
                    case .exam(let config):
                        ExamSessionView(config: config, path: $path)
                    case .examHistory:
                        ExamHistoryView(path: $path)
                    case .examResult(let id):
                        ExamResultView(examID: id, path: $path)
                    }
                }
        }
    }
}
