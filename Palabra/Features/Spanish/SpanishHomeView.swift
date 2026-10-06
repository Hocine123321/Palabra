import SwiftUI

/// Root of the Spanish tab: a list of pages. Rows link by `Router.Destination`
/// value only; `RootView` resolves destinations, so this feature never imports
/// another feature's views.
struct SpanishHomeView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: Router.Destination.vocabulary) {
                    Label("Vocabulary", systemImage: "text.book.closed")
                        .font(Theme.Font.rowTitle)
                }
                .accessibilityIdentifier("spanishRow.vocabulary")
            }
            .themedSection()
        }
        .creamScreen()
        .navigationTitle("Spanish")
    }
}
