import SwiftUI

struct DeckRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: DeckKind
    let counts: DeckCounts
}

/// Deck name for display: the system deck is localized, user decks are shown as typed.
struct DeckTitle: View {
    let name: String
    let kind: DeckKind

    var body: some View {
        if kind == .vocabulary {
            Text("Vocabulary")
        } else {
            Text(verbatim: name)
        }
    }
}

struct StudyHomeView: View {
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var rows: [DeckRow] = []
    @State private var showNewDeck = false

    private var totalDue: Int { rows.reduce(0) { $0 + $1.counts.due } }
    private var totalNew: Int { rows.reduce(0) { $0 + $1.counts.new } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if rows.isEmpty {
                        EmptyStateView(
                            systemImage: "rectangle.stack",
                            title: "No decks yet",
                            message: "Words you add to the library appear here automatically. You can also make a deck from your notes."
                        )
                    } else {
                        reviewAllButton
                        ForEach(rows) { row in
                            Button { path.append(.deck(row.id)) } label: { deckCard(row) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Study")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewDeck = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Deck from Notes")
                    .accessibilityIdentifier("newDeckButton")
            }
        }
        .sheet(isPresented: $showNewDeck, onDismiss: { reload() }) {
            NewDeckFromNotesView { id in path.append(.deck(id)) }
        }
        .onAppear {
            environment.syncVocabularyCards()
            reload()
        }
    }

    private var reviewAllButton: some View {
        Button { path.append(.review(nil)) } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                Text("Review All Due")
                Spacer()
                Text("\(totalDue) due · \(totalNew) new")
                    .font(.subheadline)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(totalDue + totalNew == 0)
        .accessibilityIdentifier("reviewAllButton")
    }

    private func deckCard(_ row: DeckRow) -> some View {
        GlassSurface {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    DeckTitle(name: row.name, kind: row.kind)
                        .font(Theme.Font.serif(20))
                        .foregroundStyle(Theme.ink)
                    Text("\(row.counts.total) cards")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text("\(row.counts.due) due").font(.subheadline).foregroundStyle(Theme.accent)
                    Text("\(row.counts.new) new").font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func reload() {
        let counts = environment.cards.counts(now: Date())
        rows = environment.cards.decks().map {
            DeckRow(id: $0.id, name: $0.name, kind: $0.kind, counts: counts[$0.id] ?? DeckCounts())
        }
    }
}
