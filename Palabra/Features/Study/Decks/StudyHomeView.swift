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

/// A stable muted tint per deck. Claude Orange is left out: it is reserved for actions.
enum DeckTint {
    static func color(for deckID: UUID) -> Color {
        let muted = Array(Theme.tileTints.dropFirst())
        let seed = deckID.uuidString.utf8.reduce(UInt32(0)) { $0 &* 31 &+ UInt32($1) }
        return muted[Int(seed % UInt32(muted.count))]
    }
}

/// A flat capsule progress track (fill on the ground, orange fill on top). Sits on glass or on a bar.
struct StudyProgressTrack: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        Capsule(style: .continuous)
            .fill(Theme.fill)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, fraction))))
                        .animation(Motion.reduced(Motion.quick), value: fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A ring that fills as today's reviews are done.
struct StudyProgressRing: View {
    let fraction: Double
    let label: Int
    var track: Color = Theme.fill
    var progress: Color = Theme.accent
    var ink: Color = Theme.ink
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(progress, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.reduced(Motion.standard), value: fraction)
            Text(verbatim: "\(label)")
                .font(Theme.Font.heading.monospacedDigit())
                .foregroundStyle(ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Seven small bars: answers per day for the last week, today on the trailing side.
struct StudyWeekBars: View {
    let counts: [Int]
    var active: Color = Theme.accent
    var idle: Color = Theme.fill

    var body: some View {
        let peak = max(1, counts.max() ?? 1)
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs + 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                Capsule(style: .continuous)
                    .fill(index == counts.count - 1 ? active : (count == 0 ? idle : active.opacity(0.45)))
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
    @State private var lastExamPercent: Int?

    private var totalDue: Int { rows.reduce(0) { $0 + $1.counts.due } }
    private var totalNew: Int { rows.reduce(0) { $0 + $1.counts.new } }

    var body: some View {
        ZStack {
            ScreenBackdrop(style: .rich)
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if rows.isEmpty {
                        EmptyStateView(
                            systemImage: "rectangle.stack",
                            title: "No decks yet",
                            message: "Words you add to the library appear here automatically. You can also make a deck from your notes."
                        )
                        examTile
                        notesTile
                    } else {
                        todayCard
                        examTile
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
        let nothingToDo = totalDue + totalNew == 0
        return CutoutCard(tint: Theme.tileTints[1]) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md + 2) {
                    StudyProgressRing(
                        fraction: planned == 0 ? 0 : Double(stats.reviewedToday) / Double(planned),
                        label: stats.reviewedToday,
                        track: Color.white.opacity(0.5),
                        progress: Theme.accentDeep,
                        ink: Theme.onTint,
                        size: 88
                    )
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Today").font(.footnote.weight(.bold)).opacity(0.65)
                        if nothingToDo {
                            Text("Nothing due today").font(Theme.Font.heading)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                                stat(totalDue, caption: "due")
                                stat(totalNew, caption: "new")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    Group {
                        if stats.streak > 0 {
                            Label("\(stats.streak)-day streak", systemImage: "flame.fill")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("streakLabel")
                        } else {
                            Text("Review a card to start a streak").font(.subheadline).opacity(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StudyWeekBars(counts: stats.lastSevenDays, active: Theme.accentDeep, idle: Color.white.opacity(0.5))
                }
                reviewAllButton
            }
            .padding(Theme.Spacing.md + 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
    }

    /// A big number with its word under it: "39 / due". Never wraps, so a long count cannot push the card around.
    private func stat(_ value: Int, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(value)")
                .font(Theme.Font.display.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.subheadline.weight(.semibold)).opacity(0.65)
        }
    }

    private var reviewAllButton: some View {
        Button { path.append(.review(nil)) } label: {
            Label("Review All Due", systemImage: "play.fill")
        }
        .buttonStyle(.primary)
        .disabled(totalDue + totalNew == 0)
        .accessibilityIdentifier("todayCard")
    }

    // MARK: - Exam

    private var examTile: some View {
        Button { path.append(.examSetup) } label: {
            GlassSurface {
                HStack(spacing: Theme.Spacing.md) {
                    IconTile(systemImage: "checklist", tint: Theme.tileTints[3], size: 52)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Exam").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        Text("Test yourself on your words: meaning, typing, grammar, listening and more.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                        if let lastExamPercent {
                            Text("Last exam: \("\(lastExamPercent)%")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accentDeep)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                }
                .padding(Theme.Spacing.md)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("examTile")
    }

    // MARK: - Decks

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.Font.heading)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    private func deckCard(_ row: DeckRow) -> some View {
        let started = row.counts.total == 0 ? 0 : Double(row.counts.total - row.counts.new) / Double(row.counts.total)
        return GlassSurface {
            HStack(spacing: Theme.Spacing.sm) {
                Button { path.append(.deck(row.id)) } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        IconTile(
                            systemImage: row.kind == .vocabulary ? "book.closed" : "rectangle.stack",
                            tint: DeckTint.color(for: row.id),
                            size: 52
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            DeckTitle(name: row.name, kind: row.kind)
                                .font(Theme.Font.heading)
                                .foregroundStyle(Theme.ink)
                            FlowLayout(spacing: Theme.Spacing.sm) {
                                countChip(Text("\(row.counts.due) due"), highlighted: row.counts.due > 0)
                                countChip(Text("\(row.counts.new) new"), highlighted: false)
                                Text("\(row.counts.total) cards")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            StudyProgressTrack(fraction: started)
                        }
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
                            .foregroundStyle(Theme.onTint)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Review This Deck")
                    .accessibilityIdentifier("deckReviewButton")
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    /// A flat count pill on a deck card: orange when there is something due, quiet otherwise.
    private func countChip(_ text: Text, highlighted: Bool) -> some View {
        text
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(highlighted ? Theme.onTint : Theme.inkSecondary)
            .padding(.horizontal, Theme.Spacing.sm + 1)
            .padding(.vertical, 4)
            .background(highlighted ? Theme.accent : Theme.fill, in: Capsule(style: .continuous))
    }

    private var notesTile: some View {
        Button { showNewDeck = true } label: {
            Label("Make a deck from notes", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassAction)
        .accessibilityIdentifier("newDeckTile")
    }

    private func reload() {
        let now = Date()
        let counts = environment.cards.counts(now: now)
        rows = environment.cards.decks().map {
            DeckRow(id: $0.id, name: $0.name, kind: $0.kind, counts: counts[$0.id] ?? DeckCounts())
        }
        stats = environment.cards.reviewStats(now: now)
        lastExamPercent = environment.exams.recent(limit: 1).first.map { Int(($0.fraction * 100).rounded()) }
    }
}
