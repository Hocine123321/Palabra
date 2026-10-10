import SwiftUI

enum SolveRoute: Hashable {
    case result(UUID)
}

/// The Solve tab: its own navigation stack.
struct SolveRootView: View {
    @State private var path: [SolveRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            SolveHomeView(path: $path)
                .navigationDestination(for: SolveRoute.self) { route in
                    switch route {
                    case .result(let id): SolveResultView(entryID: id)
                    }
                }
        }
    }
}
