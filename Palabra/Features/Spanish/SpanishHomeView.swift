import SwiftUI

/// Root of the Spanish tab: a list of pages. Rows link by `Router.Destination`
/// value only; `RootView` resolves destinations, so this feature never imports
/// another feature's views.
struct SpanishHomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var needCount = 0

    var body: some View {
        List {
            Section {
                NavigationLink(value: Router.Destination.vocabulary) {
                    Label("Vocabulary", systemImage: "text.book.closed")
                        .font(Theme.Font.rowTitle)
                }
                .accessibilityIdentifier("spanishRow.vocabulary")
                NavigationLink(value: Router.Destination.artifacts) {
                    Label("Artifacts", systemImage: "sparkles")
                        .font(Theme.Font.rowTitle)
                }
                .accessibilityIdentifier("spanishRow.artifacts")
                NavigationLink(value: Router.Destination.needReview) {
                    HStack {
                        Label("Need Review", systemImage: "flag")
                            .font(Theme.Font.rowTitle)
                        Spacer()
                        if needCount > 0 {
                            Text(verbatim: "\(needCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .accessibilityValue(Text(verbatim: "\(needCount)"))
                .accessibilityIdentifier("spanishRow.needReview")
            }
            .themedSection()
        }
        .creamScreen()
        .navigationTitle("Spanish")
        .onAppear {
            environment.syncReviewNeeds()
            needCount = environment.review.openCount()
        }
    }
}
