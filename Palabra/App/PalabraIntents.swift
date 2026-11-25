import AppIntents
import Foundation
import Observation

/// What a Shortcut or the Action button asked the app to do. The intent only leaves a note here; `RootView` carries
/// it out once the app is open, because only the app's UI knows how to navigate.
enum PendingAppAction: Equatable {
    case randomWord
    case openStudy
}

@MainActor
@Observable
final class IntentBridge {
    static let shared = IntentBridge()
    var pending: PendingAppAction?
}

struct RandomWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Random Word"
    static let description = IntentDescription("Opens a random word from your library.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.shared.pending = .randomWord
        return .result()
    }
}

struct OpenStudyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Study"
    static let description = IntentDescription("Opens the Study tab, where your cards are waiting.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.shared.pending = .openStudy
        return .result()
    }
}

/// Makes both actions show up in Shortcuts, Siri and the Action button picker with no setup.
struct PalabraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RandomWordIntent(),
            phrases: ["Random word in \(.applicationName)"],
            shortTitle: "Random Word",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: OpenStudyIntent(),
            phrases: ["Study in \(.applicationName)"],
            shortTitle: "Open Study",
            systemImageName: "rectangle.stack"
        )
    }
}
