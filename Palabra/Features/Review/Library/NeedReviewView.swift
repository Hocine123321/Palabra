import SwiftUI

/// The Need Review page: words an artifact (or later, the person) flagged, weakest first.
/// Only the person can clear a need ("Mark as learned"); artifacts cannot.
struct NeedReviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var rows: [NeedRow] = []

    struct NeedRow: Identifiable, Equatable {
        let id: UUID
        let wordID: UUID
        let headword: String
        let translation: String
        let note: String
        let score: Double
        let flagCount: Int
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(systemImage: "flag", title: "Nothing to review", message: "Words your artifacts flag will show up here.")
                    .frame(maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            rowView(row)
                                .swipeActions(edge: .trailing) {
                                    Button("Mark as learned") { markLearned(row) }
                                        .tint(Theme.accent)
                                }
                        }
                    }
                    .themedSection()
                }
                .creamScreen()
            }
        }
        .navigationTitle("Need Review")
        .onAppear(perform: reload)
    }

    private func rowView(_ row: NeedRow) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button { environment.router.openWord(row.wordID) } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(verbatim: row.headword)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.ink)
                    if !row.translation.isEmpty {
                        Text(verbatim: row.translation)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    if !row.note.isEmpty {
                        Text(verbatim: row.note)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Text(verbatim: "\(Int((row.score * 100).rounded()))% · ×\(row.flagCount)")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openNeedWordButton")
            Button { markLearned(row) } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark as learned")
            .accessibilityIdentifier("markLearnedButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needReviewRow")
    }

    private func reload() {
        environment.syncReviewNeeds()
        rows = environment.review.openNeeds().map {
            NeedRow(id: $0.id, wordID: $0.wordID, headword: $0.headword, translation: $0.translation, note: $0.note, score: $0.score, flagCount: $0.flagCount)
        }
    }

    private func markLearned(_ row: NeedRow) {
        environment.review.markLearned(id: row.id, now: Date())
        Motion.animate(Motion.standard) { reload() }
    }
}

/// The highlight on a word's detail page when it is flagged. `RootView` injects it into the
/// vocabulary detail screen so Vocabulary never imports Review.
struct ReviewNeedBanner: View {
    let wordID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var need: Snapshot?

    struct Snapshot: Equatable {
        let id: UUID
        let note: String
        let flagCount: Int
    }

    var body: some View {
        if let need {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Needs review", systemImage: "flag.fill")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.accent)
                if !need.note.isEmpty {
                    Text(verbatim: need.note)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
                Button("Mark as learned") {
                    environment.review.markLearned(id: need.id, now: Date())
                    Motion.animate(Motion.standard) { load() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("markLearnedBannerButton")
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reviewBanner")
        } else {
            Color.clear.frame(height: 0).onAppear(perform: load)
        }
    }

    private func load() {
        need = environment.review.openNeed(wordID: wordID).map { Snapshot(id: $0.id, note: $0.note, flagCount: $0.flagCount) }
    }
}
