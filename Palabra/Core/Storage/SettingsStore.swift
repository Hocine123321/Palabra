import Foundation

/// Small non-secret settings that persist across launches.
final class SettingsStore {
    enum LibraryLayout: String {
        case grid
        case list
    }

    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let selectedModelID = "selectedModelID"
        static let selectedTTSModelID = "selectedTTSModelID"
        static let libraryLayout = "libraryLayout"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let appearanceMode = "appearanceMode"
        static let appLanguage = "appLanguage"
        static let aiLanguage = "aiLanguage"
        static let organizerSettings = "organizerSettings"
        static let retryPolicy = "retryPolicy"
        static let newCardsPerDay = "newCardsPerDay"
        static let assistantSettings = "assistantSettings"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedModelID: String? {
        get { defaults.string(forKey: Keys.selectedModelID) }
        set { defaults.set(newValue, forKey: Keys.selectedModelID) }
    }

    var selectedTTSModelID: String? {
        get { defaults.string(forKey: Keys.selectedTTSModelID) }
        set { defaults.set(newValue, forKey: Keys.selectedTTSModelID) }
    }

    var libraryLayout: LibraryLayout {
        get { LibraryLayout(rawValue: defaults.string(forKey: Keys.libraryLayout) ?? "") ?? .grid }
        set { defaults.set(newValue.rawValue, forKey: Keys.libraryLayout) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearanceMode) }
    }

    var appLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Keys.appLanguage) }
    }

    var aiLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: defaults.string(forKey: Keys.aiLanguage) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Keys.aiLanguage) }
    }

    var organizerSettings: OrganizerSettings {
        get {
            guard let data = defaults.data(forKey: Keys.organizerSettings),
                  let value = try? JSONDecoder().decode(OrganizerSettings.self, from: data) else { return .default }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.organizerSettings) }
    }

    var assistantSettings: AssistantSettings {
        get {
            guard let data = defaults.data(forKey: Keys.assistantSettings),
                  let value = try? JSONDecoder().decode(AssistantSettings.self, from: data) else { return .default }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.assistantSettings) }
    }

    /// Daily cap on brand-new flashcards introduced in review sessions.
    var newCardsPerDay: Int {
        get { (defaults.object(forKey: Keys.newCardsPerDay) as? Int) ?? 20 }
        set { defaults.set(max(0, newValue), forKey: Keys.newCardsPerDay) }
    }

    var retryPolicy: RetryPolicy {
        get {
            guard let data = defaults.data(forKey: Keys.retryPolicy),
                  let value = try? JSONDecoder().decode(RetryPolicy.self, from: data) else { return .default }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.retryPolicy) }
    }
}
