import SwiftUI

private struct CardRow: Identifiable {
    let id: UUID
    let front: String
    let back: String
}

/// Cards of one deck, a Review button, and (for your own decks) deletion.
struct DeckDetailView: View {
    let deckID: UUID
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var name = ""
    @State private var kind: DeckKind = .user
    @State private var rows: [CardRow] = []
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                Button { path.append(.review(deckID)) } label: {
                    Label("Review This Deck", systemImage: "play.circle.fill")
                }
                .disabled(rows.isEmpty)
                .accessibilityIdentifier("reviewDeckButton")
            }
            .themedSection()
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: row.front).font(Theme.Font.rowTitle)
                        Text(verbatim: row.back).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .themedSection()
            if kind == .user {
                Section {
                    Button("Delete Deck", role: .destructive) { showDeleteConfirm = true }
                }
                .themedSection()
            }
        }
        .creamScreen()
        .navigationTitle(kind == .vocabulary ? Text("Vocabulary") : Text(verbatim: name))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this deck?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Deck", role: .destructive) {
                environment.cards.deleteDeck(id: deckID)
                path.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { reload() }
    }

    private func reload() {
        guard let deck = environment.cards.decks().first(where: { $0.id == deckID }) else {
            path.removeAll()
            return
        }
        name = deck.name
        kind = deck.kind
        rows = environment.cards.cards(inDeck: deckID).map { CardRow(id: $0.id, front: $0.front, back: $0.back) }
    }
}
