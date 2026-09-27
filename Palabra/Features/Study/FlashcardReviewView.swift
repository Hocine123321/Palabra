import SwiftUI

/// One-card-at-a-time review flow: tap to flip, then grade recall with
/// SM-2's four buttons. Loads its due-card queue once on appear so grading
/// mid-session doesn't reshuffle it.
struct FlashcardReviewView: View {
    let subject: String?
    @Environment(AppEnvironment.self) private var environment
    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var isFlipped = false
    @State private var reviewedCount = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if queue.isEmpty || index >= queue.count {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: reviewedCount > 0 ? "All caught up" : "Nothing due right now",
                    message: reviewedCount > 0
                        ? "You reviewed \(reviewedCount) card\(reviewedCount == 1 ? "" : "s"). Great work."
                        : "There are no flashcards due for review in this subject yet."
                )
            } else {
                content
            }
        }
        .navigationTitle(subject ?? "Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            queue = environment.flashcardRepository.dueCards(subject: subject, now: Date())
        }
    }

    private var content: some View {
        let card = queue[index]
        return VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("\(index + 1) of \(queue.count)").font(.caption).foregroundStyle(Theme.inkSecondary)
            GlassSurface {
                VStack(spacing: Theme.Spacing.md) {
                    Text(card.subject).font(.caption).foregroundStyle(Theme.inkSecondary)
                    Text(isFlipped ? card.back : card.front)
                        .font(Theme.Font.serif(22))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    if !isFlipped, let hint = card.hint, !hint.isEmpty {
                        Text("Hint: \(hint)").font(.footnote).foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(minHeight: 200)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.standard) { isFlipped.toggle() } }
            .padding(.horizontal, Theme.Spacing.md)

            if isFlipped {
                gradeButtons(for: card)
            } else {
                Button("Show Answer") { withAnimation(Motion.standard) { isFlipped = true } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            Spacer()
        }
    }

    private func gradeButtons(for card: Flashcard) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(SpacedRepetition.Grade.allCases, id: \.self) { candidateGrade in
                Button(candidateGrade.label) { submitGrade(card, candidateGrade) }
                    .buttonStyle(.bordered)
                    .tint(tint(for: candidateGrade))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func tint(for grade: SpacedRepetition.Grade) -> Color {
        switch grade {
        case .again: return Theme.error
        case .hard: return Theme.inkSecondary
        case .good: return Theme.accent
        case .easy: return Theme.accent
        }
    }

    private func submitGrade(_ card: Flashcard, _ grade: SpacedRepetition.Grade) {
        environment.flashcardRepository.review(id: card.id, grade: grade, now: Date())
        reviewedCount += 1
        withAnimation(Motion.standard) {
            isFlipped = false
            index += 1
        }
    }
}
