import Foundation

/// Small non-secret settings that persist across launches.
final class SettingsStore {
    enum LibraryLayout: String {
        case grid
        case list
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let selectedModelID = "selectedModelID"
        static let libraryLayout = "libraryLayout"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedModelID: String? {
        get { defaults.string(forKey: Keys.selectedModelID) }
        set { defaults.set(newValue, forKey: Keys.selectedModelID) }
    }

    var libraryLayout: LibraryLayout {
        get { LibraryLayout(rawValue: defaults.string(forKey: Keys.libraryLayout) ?? "") ?? .grid }
        set { defaults.set(newValue.rawValue, forKey: Keys.libraryLayout) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }
}
