import SwiftUI

/// Root of the Spanish tab: a hub of cards. Cards link by `Router.Destination`
/// value only; `RootView` resolves destinations, so this feature never imports
/// another feature's views.
struct SpanishHomeView: View {
    @Environment(AppEnvironment.self) private var environment
    /// Cards due on the Study tab and the way to get there; the App layer supplies both, so this feature never imports Study.
    var studyDue = 0
    var onOpenStudy: (() -> Void)?

    @State private var needCount = 0
    @State private var summary = HubSummary.empty

    private var wordCount: Int { summary.wordCount }
    private var recentWords: [HubSummary.RecentWord] { summary.recent }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                NavigationLink(value: Router.Destination.vocabulary) {
                    libraryCard
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityIdentifier("spanishRow.vocabulary")

                HStack(spacing: Theme.Spacing.md) {
                    NavigationLink(value: Router.Destination.chatList) {
                        compactCard(title: "Chat", systemImage: "bubble.left.and.bubble.right", tint: Theme.tileTints[2])
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityIdentifier("spanishRow.chat")

                    NavigationLink(value: Router.Destination.artifacts) {
                        compactCard(title: "Artifacts", systemImage: "sparkles", tint: Theme.tileTints[1])
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityIdentifier("spanishRow.artifacts")
                }

                HStack(spacing: Theme.Spacing.md) {
                    NavigationLink(value: Router.Destination.needReview) {
                        compactCard(title: "Need Review", systemImage: "flag", tint: Theme.tileTints[0], badge: needCount, badgeTint: Theme.tileTints[0])
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityValue(Text(verbatim: "\(needCount)"))
                    .accessibilityIdentifier("spanishRow.needReview")

                    if onOpenStudy != nil {
                        Button { onOpenStudy?() } label: {
                            compactCard(title: "Study", systemImage: "rectangle.stack", tint: Theme.tileTints[1], badge: studyDue, badgeTint: Theme.tileTints[1])
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.97))
                        .accessibilityIdentifier("spanishRow.study")
                    }
                }
                if let highlight = summary.highlight {
                    Button { environment.router.openWord(highlight.id) } label: { wordOfTheDayCard(highlight) }
                        .buttonStyle(PressScaleStyle(scale: 0.97))
                        .accessibilityIdentifier("spanishRow.wordOfDay")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background { ScreenBackdrop(style: .rich) }
        .navigationTitle("Spanish")
        .onAppear {
            environment.syncReviewNeeds()
            needCount = environment.review.openCount()
            summary = HubSummary(newestFirst: environment.repository.allWords())
        }
    }

    /// The Library hero: a muted cutout with the word count and the newest words as small tiles.
    private var libraryCard: some View {
        let inset = Theme.Spacing.md + 2
        let tileShape = RoundedRectangle(cornerRadius: Theme.Radius.sheet - inset, style: .continuous)
        return CutoutCard(tint: Theme.tileTints[4]) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm + 4) {
                    IconTile(systemImage: "text.book.closed", tint: Color.white.opacity(0.45), size: 40)
                    Text("Vocabulary")
                        .font(Theme.Font.title)
                    Spacer(minLength: Theme.Spacing.sm)
                    if wordCount > 0 {
                        Text(verbatim: "\(wordCount)")
                            .font(Theme.Font.heading)
                    }
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.45), in: Circle())
                        .accessibilityHidden(true)
                }
                if !recentWords.isEmpty {
                    HStack(spacing: Theme.Spacing.sm + 2) {
                        ForEach(recentWords) { word in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: word.spanish)
                                    .font(Theme.Font.tile)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                if !word.translation.isEmpty {
                                    Text(verbatim: word.translation)
                                        .font(.caption2.weight(.medium))
                                        .opacity(0.65)
                                        .lineLimit(1)
                                }
                            }
                                .foregroundStyle(Theme.onTint)
                                .frame(maxWidth: .infinity, minHeight: 72, alignment: .bottomLeading)
                                .padding(10)
                                .background(Theme.tint(for: word.key), in: tileShape)
                                .overlay { tileShape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1) }
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(inset)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
    }

    /// Chat and Artifacts: two glass cards side by side.
    private func compactCard(title: LocalizedStringKey, systemImage: String, tint: Color, badge: Int = 0, badgeTint: Color = Theme.tileTints[0]) -> some View {
        GlassSurface(cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm + 4) {
                HStack(alignment: .top) {
                    IconTile(systemImage: systemImage, tint: tint, size: 40)
                    Spacer(minLength: Theme.Spacing.sm)
                    if badge > 0 {
                        Chip(text: "\(badge)", tint: badgeTint)
                    }
                }
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.ink)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        }
    }

    /// One saved word, big, on its own colour: the same word all day. Tap to open it.
    private func wordOfTheDayCard(_ word: HubSummary.Highlight) -> some View {
        CutoutCard(tint: Theme.tint(for: word.key)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label("Word of the day", systemImage: "sun.max.fill")
                        .font(.footnote.weight(.bold))
                        .opacity(0.7)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.45), in: Circle())
                        .accessibilityHidden(true)
                }
                Text(verbatim: word.spanish)
                    .font(Theme.Font.display)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if !word.translation.isEmpty {
                    Text(verbatim: word.translation)
                        .font(.title3.weight(.medium))
                        .opacity(0.75)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md + 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
    }
}
