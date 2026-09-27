import Foundation
import SwiftData
import Observation

/// The app's single dependency container and reactive settings surface.
/// Views read `AIClient`/`WordRepository`/`ModelCatalogue` from here rather
/// than constructing services themselves; `KeychainStore`/`SettingsStore`
/// stay private and are exposed only through this object's tracked
/// properties, so SwiftUI observes one thing instead of polling storage.
@MainActor
@Observable
final class AppEnvironment {
    let ai: AIClient
    let repository: WordRepository
    let flashcardRepository: FlashcardRepository
    let catalogue: ModelCatalogue
    var router = Router()

    private let keychain: KeychainStore
    private let settings: SettingsStore

    private(set) var hasAPIKey: Bool
    var selectedModelID: String? { didSet { settings.selectedModelID = selectedModelID } }
    var libraryLayout: SettingsStore.LibraryLayout { didSet { settings.libraryLayout = libraryLayout } }
    var appearanceMode: SettingsStore.AppearanceMode { didSet { settings.appearanceMode = appearanceMode } }
    var appLanguage: SupportedLanguage { didSet { settings.appLanguage = appLanguage } }
    var aiLanguage: SupportedLanguage { didSet { settings.aiLanguage = aiLanguage } }
    var hasCompletedOnboarding: Bool { didSet { settings.hasCompletedOnboarding = hasCompletedOnboarding } }

    init(ai: AIClient, repository: WordRepository, flashcardRepository: FlashcardRepository, catalogue: ModelCatalogue, keychain: KeychainStore, settings: SettingsStore) {
        self.ai = ai
        self.repository = repository
        self.flashcardRepository = flashcardRepository
        self.catalogue = catalogue
        self.keychain = keychain
        self.settings = settings
        hasAPIKey = keychain.read() != nil
        selectedModelID = settings.selectedModelID
        libraryLayout = settings.libraryLayout
        appearanceMode = settings.appearanceMode
        appLanguage = settings.appLanguage
        aiLanguage = settings.aiLanguage
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        catalogue.loadCacheIfPresent()
    }

    var apiKey: String? { keychain.read() }

    var selectedModel: AIModel? {
        guard let id = selectedModelID else { return nil }
        return catalogue.models.first { $0.id == id }
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        let ok = keychain.save(value)
        hasAPIKey = keychain.read() != nil
        return ok
    }

    func removeAPIKey() {
        keychain.delete()
        hasAPIKey = false
    }

    static func live(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(
            ai: GeminiClient(),
            repository: SwiftDataWordRepository(context: modelContext),
            flashcardRepository: SwiftDataFlashcardRepository(context: modelContext),
            catalogue: ModelCatalogue(),
            keychain: KeychainStore(),
            settings: SettingsStore()
        )
    }
}
