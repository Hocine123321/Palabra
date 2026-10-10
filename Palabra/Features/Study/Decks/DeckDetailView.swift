import SwiftUI

private struct CardRow: Identifiable {
    enum Status: Equatable { case new, due, later(TimeInterval) }
    let id: UUID
    let front: String
    let back: String
    let status: Status
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
    @State private var showAddCard = false
    @State private var query = ""

    private var visibleRows: [CardRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.front.localizedCaseInsensitiveContains(needle) || $0.back.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    summary("\(rows.count)", "Cards")
                    Divider()
                    summary("\(dueCount)", "Due", highlight: dueCount > 0)
                    Divider()
                    summary("\(newCount)", "New")
                }
                .frame(height: 52)
                Button { path.append(.review(deckID)) } label: {
                    Label("Review This Deck", systemImage: "play.circle.fill")
                }
                .disabled(rows.isEmpty)
                .accessibilityIdentifier("reviewDeckButton")
                if kind == .user {
                    Button { showAddCard = true } label: {
                        Label("Add Card", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addCardButton")
                }
            }
            .themedSection()
            Section {
                ForEach(visibleRows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(verbatim: row.front).font(Theme.Font.rowTitle)
                            Text(verbatim: row.back).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        statusBadge(row.status)
                    }
                    .swipeActions {
                        if kind == .user {
                            Button("Delete", role: .destructive) {
                                environment.cards.deleteCard(id: row.id)
                                reload()
                            }
                        }
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
        .searchable(text: $query)
        .sheet(isPresented: $showAddCard) { AddCardView(deckID: deckID, onAdded: { reload() }) }
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
        let now = Date()
        rows = environment.cards.cards(inDeck: deckID).map { card in
            let status: CardRow.Status = card.phase == .new ? .new : (card.due <= now ? .due : .later(card.due.timeIntervalSince(now)))
            return CardRow(id: card.id, front: card.front, back: card.back, status: status)
        }
    }

    private var dueCount: Int { rows.filter { $0.status == .due }.count }
    private var newCount: Int { rows.filter { $0.status == .new }.count }

    private func summary(_ value: String, _ caption: LocalizedStringKey, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(Theme.Font.heading).foregroundStyle(highlight ? Theme.accent : Theme.ink)
            Text(caption).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusBadge(_ status: CardRow.Status) -> some View {
        switch status {
        case .new: Text("New").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
        case .due: Text("Due").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
        case .later(let seconds): Text(verbatim: IntervalLabel.text(seconds: seconds)).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }
}
