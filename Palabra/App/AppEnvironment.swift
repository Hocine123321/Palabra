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
    let catalogue: ModelCatalogue
    let ttsCatalogue: ModelCatalogue
    let pronunciation = PronunciationService()
    var router = Router()

    private let keychain: KeychainStore
    private let settings: SettingsStore

    private(set) var hasAPIKey: Bool
    var selectedModelID: String? { didSet { settings.selectedModelID = selectedModelID } }
    var selectedTTSModelID: String? { didSet { settings.selectedTTSModelID = selectedTTSModelID } }
    var libraryLayout: SettingsStore.LibraryLayout { didSet { settings.libraryLayout = libraryLayout } }
    var appearanceMode: SettingsStore.AppearanceMode { didSet { settings.appearanceMode = appearanceMode } }
    var appLanguage: SupportedLanguage { didSet { settings.appLanguage = appLanguage } }
    var aiLanguage: SupportedLanguage { didSet { settings.aiLanguage = aiLanguage } }
    var hasCompletedOnboarding: Bool { didSet { settings.hasCompletedOnboarding = hasCompletedOnboarding } }

    init(ai: AIClient, repository: WordRepository, catalogue: ModelCatalogue, ttsCatalogue: ModelCatalogue, keychain: KeychainStore, settings: SettingsStore) {
        self.ai = ai
        self.repository = repository
        self.catalogue = catalogue
        self.ttsCatalogue = ttsCatalogue
        self.keychain = keychain
        self.settings = settings
        hasAPIKey = keychain.read() != nil
        selectedModelID = settings.selectedModelID
        selectedTTSModelID = settings.selectedTTSModelID
        libraryLayout = settings.libraryLayout
        appearanceMode = settings.appearanceMode
        appLanguage = settings.appLanguage
        aiLanguage = settings.aiLanguage
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        catalogue.loadCacheIfPresent()
        ttsCatalogue.loadCacheIfPresent()
    }

    var apiKey: String? { keychain.read() }

    var selectedModel: AIModel? {
        guard let id = selectedModelID else { return nil }
        return catalogue.models.first { $0.id == id }
    }

    var selectedTTSModel: AIModel? {
        guard let id = selectedTTSModelID else { return nil }
        return ttsCatalogue.models.first { $0.id == id }
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

    /// Makes sure a pronunciation (TTS) model is selected when one is
    /// available: if none is chosen yet, fetches the TTS catalogue (only when
    /// it's empty) and picks the default. Lets pronunciation work right after
    /// the API key is saved — and for people who already had a key before
    /// pronunciation existed — without a trip to Settings. Never overrides an
    /// existing choice; failures are silent here (Settings shows catalogue
    /// errors, and `PronunciationService.generate` reports "no model").
    func ensureTTSModelSelected() async {
        guard selectedTTSModelID == nil, let key = self.apiKey else { return }
        if ttsCatalogue.models.isEmpty {
            await ttsCatalogue.refresh(apiKey: key, using: ai)
        }
        if selectedTTSModelID == nil {
            selectedTTSModelID = DefaultModelPicker.pick(from: ttsCatalogue.models)?.id
        }
    }

    /// Best-effort, silent kick-off of pronunciation generation — used right
    /// after a word is saved or regenerated. With no API key this does
    /// nothing: the person just saved a word, and surfacing a
    /// pronunciation-specific error at that moment would be a non sequitur.
    /// If a key exists but no pronunciation model is selected yet, one is
    /// chosen automatically first (see `ensureTTSModelSelected`); if none is
    /// available the attempt quietly ends there. The pronunciation button's
    /// own manual (re)try surfaces those same failures explicitly instead,
    /// via `PronunciationService.generate`.
    func requestPronunciationIfConfigured(for word: Word) {
        guard hasAPIKey else { return }
        Task {
            await ensureTTSModelSelected()
            guard selectedTTSModel != nil else { return }
            await pronunciation.generate(for: word, using: self)
        }
    }

    static func live(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(
            ai: GeminiClient(),
            repository: SwiftDataWordRepository(context: modelContext),
            catalogue: ModelCatalogue(),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply),
            keychain: KeychainStore(),
            settings: SettingsStore()
        )
    }
}
