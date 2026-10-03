import SwiftUI

/// The app's top-level tabs.
enum AppTab: Hashable {
    case vocabulary
    case study
    case settings
}

@MainActor
@Observable
final class Router {
    /// Pushed screens of the Vocabulary tab only. Study and Settings own their own stacks.
    enum Destination: Hashable {
        case wordDetail(UUID)
    }

    var path = NavigationPath()
    var tab: AppTab = .vocabulary

    /// Settings is its own tab, so this works the same from every tab.
    func openSettings() { tab = .settings }
    func openWord(_ id: UUID) {
        tab = .vocabulary
        path.append(Destination.wordDetail(id))
    }
}
