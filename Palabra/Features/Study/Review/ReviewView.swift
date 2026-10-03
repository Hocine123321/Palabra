import SwiftUI

/// Flip-and-grade review of due and new cards. `cardAccessory` lets the app add
/// something next to a card that came from a library word (for example pronunciation)
/// without Study knowing about vocabulary.
struct ReviewView: View {
    let deckID: UUID?
    var cardAccessory: (UUID) -> AnyView = { _ in AnyView(EmptyView()) }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReviewViewModel?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                if let card = model.current {
                    session(model: model, card: card)
                } else {
                    finished(model: model)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard model == nil else { return }
            let queue = environment.cards.studyQueue(deckID: deckID, now: Date(), newLimit: environment.newCardsPerDay)
            model = ReviewViewModel(queue: queue, repository: environment.cards)
        }
    }

    private func session(model: ReviewViewModel, card: Card) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("\(model.remaining) left")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("remainingLabel")

            GlassSurface {
                VStack(spacing: Theme.Spacing.md) {
                    HStack {
                        Spacer()
                        if let source = card.sourceWordID { cardAccessory(source) }
                    }
                    Text(verbatim: card.front)
                        .font(Theme.Font.serif(30))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("cardFront")
                    if model.isFlipped {
                        Divider()
                        Text(verbatim: card.back)
                            .font(.title3)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("cardBack")
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: 220)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.quick) { model.flip() } }
            .padding(.horizontal, Theme.Spacing.md)

            Spacer()

            if model.isFlipped {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(SRSGrade.allCases, id: \.self) { grade in
                        Button {
                            withAnimation(Motion.quick) { model.grade(grade) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(grade.title).font(.headline)
                                Text(verbatim: model.intervalLabel(for: grade)).font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(grade == .again ? Theme.error : Theme.accent)
                        .accessibilityIdentifier(grade.identifier)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            } else {
                Button {
                    withAnimation(Motion.quick) { model.flip() }
                } label: {
                    Text("Show Answer").frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.horizontal, Theme.Spacing.md)
                .accessibilityIdentifier("showAnswerButton")
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    private func finished(model: ReviewViewModel) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "All caught up",
                message: model.answered == 0 ? LocalizedStringKey("Nothing is due right now.") : LocalizedStringKey("You reviewed \(model.answered) cards.")
            )
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("doneButton")
        }
    }
}
