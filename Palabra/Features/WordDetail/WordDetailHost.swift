import SwiftUI

/// Resolves a `Router.Destination.wordDetail(id)` to its `Word`. Shows a
/// readable state if the word was deleted from elsewhere in the meantime.
struct WordDetailHost: View {
    let wordID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var word: Word?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let word {
                WordDetailView(word: word)
            } else if didLoad {
                EmptyStateView(systemImage: "questionmark.circle", title: "Word not found", message: "This word may have been deleted.")
            } else {
                ProgressView()
            }
        }
        .onAppear {
            word = environment.repository.allWords().first { $0.id == wordID }
            didLoad = true
        }
    }
}
