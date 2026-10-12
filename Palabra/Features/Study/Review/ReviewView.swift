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
            ScreenBackdrop()
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
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm + 4) {
                StudyProgressTrack(fraction: model.progress, height: 8)
                Text("\(model.remaining) left")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityIdentifier("remainingLabel")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .glassCapsule()
            .padding(.horizontal, Theme.Spacing.md)

            CutoutCard(tint: DeckTint.color(for: card.deckID)) {
                VStack(spacing: Theme.Spacing.md) {
                    HStack {
                        Spacer()
                        if let source = card.sourceWordID { cardAccessory(source) }
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: card.front)
                        .font(Theme.Font.display)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("cardFront")
                    if model.isFlipped {
                        Rectangle()
                            .fill(Theme.onTint.opacity(0.18))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                        Text(verbatim: card.back)
                            .font(Theme.Font.heading)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("cardBack")
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
            .contentShape(Rectangle())
            .onTapGesture { Motion.animate(Motion.quick) { model.flip() } }
            .padding(.horizontal, Theme.Spacing.md)

            if model.isFlipped {
                GlassSurface(cornerRadius: Theme.Radius.pill) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(SRSGrade.allCases, id: \.self) { grade in
                            Button {
                                Motion.animate(Motion.quick) { model.grade(grade) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(grade.title)
                                        .font(.headline.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(verbatim: model.intervalLabel(for: grade))
                                        .font(.caption.weight(.semibold))
                                        .opacity(0.75)
                                }
                                .foregroundStyle(grade == .hard ? Theme.ink : Theme.onTint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm + 2)
                                .background(gradeFill(grade), in: Capsule(style: .continuous))
                            }
                            .buttonStyle(GradePressStyle())
                            .accessibilityIdentifier(grade.identifier)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.md)
            } else {
                Button {
                    Motion.animate(Motion.quick) { model.flip() }
                } label: {
                    Text("Show Answer")
                }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .accessibilityIdentifier("showAnswerButton")
            }
        }
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    /// Again is apricot, Hard a quiet fill, Good Claude Orange, Easy sage.
    private func gradeFill(_ grade: SRSGrade) -> Color {
        switch grade {
        case .again: return Theme.tileTints[4]
        case .hard: return Theme.fill
        case .good: return Theme.accent
        case .easy: return Theme.tileTints[1]
        }
    }

    private func finished(model: ReviewViewModel) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "All caught up",
                message: model.answered == 0 ? LocalizedStringKey("Nothing is due right now.") : LocalizedStringKey("You reviewed \(model.answered) cards.")
            )
            if model.answered > 0 {
                let streak = environment.cards.reviewStats(now: Date()).streak
                HStack(spacing: Theme.Spacing.sm) {
                    summaryTile(value: "\(model.answered)", caption: "Reviewed")
                    summaryTile(value: model.accuracyPercent.map { "\($0)%" } ?? "–", caption: "Correct")
                    summaryTile(value: "\(streak)", caption: "Day streak")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .accessibilityIdentifier("sessionSummary")
            }
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .accessibilityIdentifier("doneButton")
        }
    }

    private func summaryTile(value: String, caption: LocalizedStringKey) -> some View {
        GlassSurface {
            VStack(spacing: Theme.Spacing.xs) {
                Text(verbatim: value).font(Theme.Font.title).foregroundStyle(Theme.ink)
                Text(caption).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
    }
}

private struct GradePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.reduced(Motion.quick), value: configuration.isPressed)
    }
}
