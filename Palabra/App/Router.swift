import SwiftUI

@MainActor
@Observable
final class Router {
    enum Destination: Hashable {
        case settings
        case wordDetail(UUID)
    }

    var path = NavigationPath()

    func openSettings() { path.append(Destination.settings) }
    func openWord(_ id: UUID) { path.append(Destination.wordDetail(id)) }
}
