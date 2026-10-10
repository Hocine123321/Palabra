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

/// A ring that fills as today's reviews are done.
struct StudyProgressRing: View {
    let fraction: Double
    let label: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.inkSecondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.reduced(Motion.standard), value: fraction)
            Text(verbatim: "\(label)")
                .font(Theme.Font.heading.monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }
}

/// Seven small bars: answers per day for the last week, today on the trailing side.
struct StudyWeekBars: View {
    let counts: [Int]

    var body: some View {
        let peak = max(1, counts.max() ?? 1)
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs + 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                Capsule()
                    .fill(index == counts.count - 1 ? Theme.accent : Theme.accent.opacity(count == 0 ? 0.18 : 0.45))
                    .frame(width: 10, height: 6 + CGFloat(count) / CGFloat(peak) * 30)
            }
        }
        .frame(height: 36, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Reviews in the last 7 days: \(counts.reduce(0, +))"))
    }
}

struct StudyHomeView: View {
    @Binding var path: [StudyRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var rows: [DeckRow] = []
    @State private var stats = StudyStats()
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
                        notesTile
                    } else {
                        todayCard
                        sectionTitle("Decks")
                        ForEach(rows) { row in
                            deckCard(row)
                        }
                        notesTile
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

    // MARK: - Today

    private var todayCard: some View {
        let planned = stats.reviewedToday + totalDue + totalNew
        return GlassSurface {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    StudyProgressRing(fraction: planned == 0 ? 0 : Double(stats.reviewedToday) / Double(planned), label: stats.reviewedToday)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Today").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                        if totalDue + totalNew == 0 {
                            Text("Nothing due today").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        } else {
                            Text("\(totalDue) due · \(totalNew) new").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        }
                        if stats.streak > 0 {
                            Label("\(stats.streak)-day streak", systemImage: "flame.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                                .accessibilityIdentifier("streakLabel")
                        } else {
                            Text("Review a card to start a streak").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    StudyWeekBars(counts: stats.lastSevenDays)
                }
                reviewAllButton
            }
            .padding(Theme.Spacing.md)
        }
        .accessibilityIdentifier("todayCard")
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
        }
        .buttonStyle(.primary)
        .disabled(totalDue + totalNew == 0)
        .accessibilityIdentifier("reviewAllButton")
    }

    // MARK: - Decks

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.sm)
    }

    private func deckCard(_ row: DeckRow) -> some View {
        let started = row.counts.total == 0 ? 0 : Double(row.counts.total - row.counts.new) / Double(row.counts.total)
        return GlassSurface {
            HStack(spacing: Theme.Spacing.sm) {
                Button { path.append(.deck(row.id)) } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        DeckTitle(name: row.name, kind: row.kind)
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.ink)
                        Text("\(row.counts.total) cards")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                        ProgressView(value: started)
                            .tint(Theme.accent)
                            .accessibilityHidden(true)
                        HStack(spacing: Theme.Spacing.md) {
                            Text("\(row.counts.due) due").foregroundStyle(row.counts.due > 0 ? Theme.accent : Theme.inkSecondary)
                            Text("\(row.counts.new) new").foregroundStyle(Theme.inkSecondary)
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("deckCard")
                if row.counts.due + row.counts.new > 0 {
                    Button { path.append(.review(row.id)) } label: {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Review This Deck")
                    .accessibilityIdentifier("deckReviewButton")
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var notesTile: some View {
        Button { showNewDeck = true } label: {
            Label("Make a deck from notes", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newDeckTile")
    }

    private func reload() {
        let now = Date()
        let counts = environment.cards.counts(now: now)
        rows = environment.cards.decks().map {
            DeckRow(id: $0.id, name: $0.name, kind: $0.kind, counts: counts[$0.id] ?? DeckCounts())
        }
        stats = environment.cards.reviewStats(now: now)
    }
}
