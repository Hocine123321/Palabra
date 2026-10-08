import SwiftUI

/// The app's top-level tabs.
enum AppTab: Hashable {
    case spanish
    case study
    case settings
}

@MainActor
@Observable
final class Router {
    /// Pushed screens of the Spanish tab only. Study and Settings own their own stacks.
    enum Destination: Hashable {
        case vocabulary
        case wordDetail(UUID)
        case artifacts
        case artifactDetail(UUID)
        case needReview
    }

    var path: [Destination] = []
    var tab: AppTab = .spanish

    /// Settings is its own tab, so this works the same from every tab.
    func openSettings() { tab = .settings }

    /// Always lands on the word with the library underneath it, so Back goes to the
    /// library (not the hub) and an already-pushed library or detail is never stacked twice.
    func openWord(_ id: UUID) {
        tab = .spanish
        path = [.vocabulary, .wordDetail(id)]
    }
}
