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
    /// What every screen calls. With resilience on (the live app) this is a
    /// `ResilientAIClient` wrapping `rawAI`; otherwise it is `rawAI` itself.
    let ai: AIClient
    /// The plain client underneath, without retries.
    let rawAI: AIClient
    /// Same as `ai` but never asks the person anything: for silent background work.
    let backgroundAI: AIClient
    /// Shared state for retries, key switching and "what should I do?" questions.
    let resilience = ResilienceCenter()
    let repository: WordRepository
    /// Flashcard decks and review history (Study tool).
    let cards: CardRepository
    let catalogue: ModelCatalogue
    let ttsCatalogue: ModelCatalogue
    let pronunciation = PronunciationService()
    /// Added while offline, waiting to be generated once the connection
    /// returns — see `WordQueueProcessor`.
    let wordQueue: WordQueueRepository
    @ObservationIgnored let queueProcessor = WordQueueProcessor()
    /// Instant online/offline snapshot, shared with the resilient client so
    /// both see the same answer. Real device state outside of tests.
    let connectivity: ConnectivityWaiting
    var router = Router()

    private let keychain: KeychainStore
    private let fallbackKeychain: KeychainStore
    private let settings: SettingsStore

    private(set) var hasAPIKey: Bool
    private(set) var hasFallbackKey: Bool
    var retryPolicy: RetryPolicy { didSet { settings.retryPolicy = retryPolicy; policyBox.value = retryPolicy } }
    @ObservationIgnored private let policyBox: PolicyBox
    var selectedModelID: String? { didSet { settings.selectedModelID = selectedModelID } }
    var selectedTTSModelID: String? { didSet { settings.selectedTTSModelID = selectedTTSModelID } }
    var libraryLayout: SettingsStore.LibraryLayout { didSet { settings.libraryLayout = libraryLayout } }
    var appearanceMode: SettingsStore.AppearanceMode { didSet { settings.appearanceMode = appearanceMode } }
    var appLanguage: SupportedLanguage { didSet { settings.appLanguage = appLanguage } }
    var aiLanguage: SupportedLanguage { didSet { settings.aiLanguage = aiLanguage } }
    var organizerSettings: OrganizerSettings { didSet { settings.organizerSettings = organizerSettings } }
    var newCardsPerDay: Int { didSet { settings.newCardsPerDay = newCardsPerDay } }
    /// Session-only progress/result of a library re-organization.
    @ObservationIgnored let organizer = LibraryOrganizer()
    var hasCompletedOnboarding: Bool { didSet { settings.hasCompletedOnboarding = hasCompletedOnboarding } }

    init(
        ai: AIClient,
        repository: WordRepository,
        catalogue: ModelCatalogue,
        ttsCatalogue: ModelCatalogue,
        keychain: KeychainStore,
        settings: SettingsStore,
        wordQueue: WordQueueRepository,
        fallbackKeychain: KeychainStore = .fallback(),
        resilient: Bool = false,
        connectivity: ConnectivityWaiting? = nil,
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil,
        cardRepository: CardRepository? = nil
    ) {
        self.rawAI = ai
        let policyBox = PolicyBox(settings.retryPolicy)
        self.policyBox = policyBox
        let center = resilience
        let resolvedConnectivity = connectivity ?? NetworkMonitor()
        self.connectivity = resolvedConnectivity
        if resilient {
            let fallbackStore = fallbackKeychain
            let wrapped = ResilientAIClient(
                base: ai,
                center: center,
                fallbackKey: { fallbackStore.read() },
                policy: { policyBox.value },
                connectivity: resolvedConnectivity,
                sleep: sleep ?? { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
            )
            self.ai = wrapped
            self.backgroundAI = wrapped.quiet()
        } else {
            self.ai = ai
            self.backgroundAI = ai
        }
        self.fallbackKeychain = fallbackKeychain
        hasFallbackKey = fallbackKeychain.read() != nil
        retryPolicy = settings.retryPolicy
        self.repository = repository
        self.cards = cardRepository ?? SwiftDataCardRepository.inMemory()
        self.catalogue = catalogue
        self.ttsCatalogue = ttsCatalogue
        self.wordQueue = wordQueue
        self.keychain = keychain
        self.settings = settings
        hasAPIKey = keychain.read() != nil
        selectedModelID = settings.selectedModelID
        selectedTTSModelID = settings.selectedTTSModelID
        libraryLayout = settings.libraryLayout
        appearanceMode = settings.appearanceMode
        appLanguage = settings.appLanguage
        aiLanguage = settings.aiLanguage
        organizerSettings = settings.organizerSettings
        newCardsPerDay = settings.newCardsPerDay
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        catalogue.loadCacheIfPresent()
        ttsCatalogue.loadCacheIfPresent()
    }

    var apiKey: String? { keychain.read() }

    /// Called when Google says the selected model no longer exists. Refreshes the list and
    /// switches to the best remaining model so the next request works, and says so.
    /// Returns the new model's name, or nil when nothing better is available.
    @discardableResult
    func repairMissingModel(isTTS: Bool = false) async -> String? {
        guard let key = apiKey else { return nil }
        let target = isTTS ? ttsCatalogue : catalogue
        await target.refresh(apiKey: key, using: rawAI)
        guard let pick = DefaultModelPicker.pick(from: target.models) else { return nil }
        if isTTS { selectedTTSModelID = pick.id } else { selectedModelID = pick.id }
        resilience.post("Your model was removed, so I switched to \(pick.displayName).", warning: false)
        return pick.displayName
    }

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
        resilience.updateHealth { $0.reset(.primary) }
        return ok
    }

    func removeAPIKey() {
        keychain.delete()
        hasAPIKey = false
        resilience.updateHealth { $0.reset(.primary) }
    }

    var fallbackAPIKey: String? { fallbackKeychain.read() }

    /// Stores the backup key. Refuses to store the same key as the primary, since
    /// it would add nothing. Returns false if it could not be saved.
    @discardableResult
    func saveFallbackKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let ok = fallbackKeychain.save(trimmed)
        hasFallbackKey = fallbackKeychain.read() != nil
        resilience.updateHealth { $0.reset(.fallback) }
        return ok
    }

    func removeFallbackKey() {
        fallbackKeychain.delete()
        hasFallbackKey = false
        resilience.updateHealth { $0.reset(.fallback) }
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
            await pronunciation.generate(for: word, using: self, quiet: true)
        }
    }

    /// Best-effort, silent: gives a freshly saved word its section and tags,
    /// reusing existing section names. Does nothing without a key/model or when
    /// the user turned auto-organizing off; a failure just leaves the word
    /// unorganized (the next "Re-organize library" picks it up).
    func requestOrganizationIfConfigured(for word: Word) {
        guard organizerSettings.autoOrganizeNewWords, hasAPIKey, let apiKey = self.apiKey, let model = selectedModel else { return }
        let id = word.id
        let input = OrganizerWordInput(word: word.spanish, translation: word.translation, partOfSpeech: word.partOfSpeech)
        let prefs = organizerSettings
        let language = aiLanguage
        let existing = Array(Set(repository.allWords().compactMap(\.category))).sorted()
        Task { [backgroundAI, repository] in
            // A failure here is logged by the resilient client itself ("Recent Problems").
            guard case .success(let result) = await backgroundAI.organizeWords([input], existingCategories: existing, settings: prefs, apiKey: apiKey, model: model, language: language),
                  let entry = result.entries.first else { return }
            var placement = LibraryTaxonomy.clean(WordPlacement(category: entry.category, tags: entry.tags))
            placement.category = LibraryTaxonomy.canonicalCategory(placement.category, known: existing)
            placement.tags = Array(placement.tags.prefix(prefs.maxTagsPerWord))
            repository.updatePlacement(id: id, category: placement.category, tags: placement.tags)
        }
    }

    /// Makes the Study tool's Vocabulary deck match the library (one card per word,
    /// headword -> translation). Idempotent and cheap; call on launch and whenever the
    /// Study tab appears. This is the only place that knows both `Word` and Study.
    func syncVocabularyCards() {
        let entries = repository.allWords().compactMap { word -> VocabularyCardEntry? in
            let front = word.spanish.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = word.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return VocabularyCardEntry(wordID: word.id, front: front, back: back)
        }
        cards.syncVocabulary(entries)
    }

    static func live(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(
            ai: GeminiClient(),
            repository: SwiftDataWordRepository(context: modelContext),
            catalogue: ModelCatalogue(),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply),
            keychain: KeychainStore(),
            settings: SettingsStore(),
            wordQueue: SwiftDataWordQueueRepository(context: modelContext),
            resilient: true,
            cardRepository: SwiftDataCardRepository(context: modelContext)
        )
    }
}

/// A tiny thread-safe holder so the retry client always reads the current policy.
final class PolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RetryPolicy
    init(_ value: RetryPolicy) { stored = value }
    var value: RetryPolicy {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
