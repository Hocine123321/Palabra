import SwiftUI
import SwiftData

/// The study planner: due-card counts per subject, a review shortcut, and
/// entry points into "notes → flashcards" and "notes → quiz" generation.
/// Reads flashcards live via `@Query`, same pattern as `LibraryView`.
struct StudyPlannerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Flashcard.dueDate) private var cards: [Flashcard]

    @State private var showingAddFlashcards = false
    @State private var justSavedCount: Int?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if cards.isEmpty {
                        EmptyStateView(
                            systemImage: "rectangle.stack.badge.plus",
                            title: "No flashcards yet",
                            message: "Paste your class notes and let AI turn them into flashcards you can review on a spaced-repetition schedule."
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        dueSummaryCard
                        subjectList
                    }

                    Button {
                        showingAddFlashcards = true
                    } label: {
                        Label("Add Flashcards from Notes", systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)

                    Button {
                        environment.router.openQuizGenerator()
                    } label: {
                        Label("Generate a Quiz from Notes", systemImage: "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Study Planner")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { environment.router.openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingAddFlashcards) {
            AddFlashcardsSheet { count in
                justSavedCount = count
            }
        }
        .alert("Flashcards Added", isPresented: Binding(get: { justSavedCount != nil }, set: { if !$0 { justSavedCount = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Saved \(justSavedCount ?? 0) flashcard\((justSavedCount ?? 0) == 1 ? "" : "s") to your study planner.")
        }
    }

    private var dueCards: [Flashcard] { cards.filter { $0.isDue() } }

    private var dueSummaryCard: some View {
        GlassSurface {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Due for review").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    Text("\(dueCards.count)").font(Theme.Font.serif(32)).foregroundStyle(Theme.ink)
                }
                Spacer()
                Button("Review Now") {
                    environment.router.openFlashcardReview(subject: nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(dueCards.isEmpty)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var subjectList: some View {
        let bySubject = Dictionary(grouping: cards, by: \.subject)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Subjects").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            ForEach(bySubject.keys.sorted(), id: \.self) { subject in
                let subjectCards = bySubject[subject] ?? []
                let dueCount = subjectCards.filter { $0.isDue() }.count
                Button {
                    environment.router.openFlashcardReview(subject: subject)
                } label: {
                    GlassSurface {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(subject).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                                Text("\(subjectCards.count) card\(subjectCards.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            if dueCount > 0 {
                                Chip(text: "\(dueCount) due")
                            }
                            Image(systemName: "chevron.right").foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
