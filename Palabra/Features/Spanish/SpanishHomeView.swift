import SwiftUI

/// Root of the Spanish tab: a hub of cards. Cards link by `Router.Destination`
/// value only; `RootView` resolves destinations, so this feature never imports
/// another feature's views.
struct SpanishHomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var needCount = 0
    @State private var wordCount = 0
    @State private var recentWords: [HubWord] = []

    /// A plain snapshot of a recent word, so the hub never holds a SwiftData model.
    private struct HubWord: Identifiable {
        let id: UUID
        let spanish: String
        let key: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                NavigationLink(value: Router.Destination.vocabulary) {
                    libraryCard
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("spanishRow.vocabulary")

                HStack(spacing: Theme.Spacing.md) {
                    NavigationLink(value: Router.Destination.chatList) {
                        compactCard(title: "Chat", systemImage: "bubble.left.and.bubble.right", tint: Theme.tileTints[2])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spanishRow.chat")

                    NavigationLink(value: Router.Destination.artifacts) {
                        compactCard(title: "Artifacts", systemImage: "sparkles", tint: Theme.tileTints[1])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spanishRow.artifacts")
                }

                NavigationLink(value: Router.Destination.needReview) {
                    needReviewCard
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(verbatim: "\(needCount)"))
                .accessibilityIdentifier("spanishRow.needReview")
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
            let all = environment.repository.allWords()
            wordCount = all.count
            recentWords = all.prefix(3).map { HubWord(id: $0.id, spanish: $0.spanish, key: $0.key) }
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
                            Text(verbatim: word.spanish)
                                .font(Theme.Font.tile)
                                .foregroundStyle(Theme.onTint)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
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
    private func compactCard(title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        GlassSurface(cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm + 4) {
                IconTile(systemImage: systemImage, tint: tint, size: 40)
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.ink)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        }
    }

    private var needReviewCard: some View {
        GlassSurface(cornerRadius: Theme.Radius.card) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemImage: "flag", tint: Theme.tileTints[0], size: 48)
                Text("Need Review")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.Spacing.sm)
                if needCount > 0 {
                    Chip(text: "\(needCount)", tint: Theme.tileTints[0])
                }
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
