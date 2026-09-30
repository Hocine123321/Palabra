import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class LibraryOrganizationTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        keychain = KeychainStore()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    // MARK: helpers

    private func content(_ word: String) -> WordContent {
        WordContent(
            word: word,
            examples: [
                .init(context: "a", spanish: "uno", english: "one"),
                .init(context: "b", spanish: "dos", english: "two"),
                .init(context: "c", spanish: "tres", english: "three")
            ],
            meaning: .init(translations: ["meaning of \(word)"], explanation: "e"),
            usage: .init(explanation: "u", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "noun", groups: [.init(label: "Forms", items: [.init(form: word, note: nil)])]),
            similarWords: [.init(word: "otro", difference: "d")]
        )
    }

    private func makeEnvironment() -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "org-\(UUID().uuidString)") ?? .standard)
        )
        env.saveAPIKey("test-api-key")
        return (env, client)
    }

    private func selectModel(_ env: AppEnvironment, _ client: MockAIClient) async {
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
    }

    @discardableResult
    private func add(_ env: AppEnvironment, _ word: String) -> Word {
        env.repository.insert(spanish: word, key: WordKey.identity(word), searchKey: WordKey.search(word), content: content(word), rawJSON: Data())
    }

    private func waitUntilDone(_ organizer: LibraryOrganizer) async {
        for _ in 0..<200 {
            if !organizer.isRunning { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: taxonomy cleaning

    func testCleanNameCollapsesWhitespaceAndCapitalizes() {
        XCTAssertEqual(LibraryTaxonomy.cleanName("  food   & drink "), "Food & drink")
        XCTAssertEqual(LibraryTaxonomy.cleanName("   "), "")
    }

    func testCleanTagsLowercasesDedupesStripsHashAndCaps() {
        let tags = LibraryTaxonomy.cleanTags(["#Verb", "verb", " Cooking ", "", "a", "b", "c", "d", "e"])
        XCTAssertEqual(tags, ["verb", "cooking", "a", "b", "c", "d"])
    }

    func testEmptyCategoryFallsBackToOther() {
        let placement = LibraryTaxonomy.clean(WordPlacement(category: "  ", tags: ["x"]))
        XCTAssertEqual(placement.category, "Other")
    }

    func testCanonicalCategoryMergesCaseAccentAndPluralVariants() {
        XCTAssertEqual(LibraryTaxonomy.canonicalCategory("foods", known: ["Food"]), "Food")
        XCTAssertEqual(LibraryTaxonomy.canonicalCategory("Emociónes", known: ["Emociones"]), "Emociones")
        XCTAssertEqual(LibraryTaxonomy.canonicalCategory("Travel", known: ["Food"]), "Travel")
    }

    // MARK: word storage

    func testWordTagsRoundTripAndEmptyClears() {
        let env = makeEnvironment().0
        let word = add(env, "gato")
        XCTAssertNil(word.category)
        XCTAssertEqual(word.tags, [])
        env.repository.updatePlacement(id: word.id, category: "Animals", tags: ["pet", "noun"])
        let found = env.repository.find(key: "gato")
        XCTAssertEqual(found?.category, "Animals")
        XCTAssertEqual(found?.tags, ["pet", "noun"])
        env.repository.clearAllPlacements()
        XCTAssertNil(env.repository.find(key: "gato")?.category)
        XCTAssertEqual(env.repository.find(key: "gato")?.tags, [])
    }

    func testExportDoesNotIncludePlacementAndImportStillWorks() throws {
        let env = makeEnvironment().0
        let word = add(env, "gato")
        env.repository.updatePlacement(id: word.id, category: "Animals", tags: ["pet"])
        let data = env.repository.exportData()
        env.repository.deleteAll()
        let result = try env.repository.importData(data)
        XCTAssertEqual(result.imported, 1)
        XCTAssertNil(env.repository.find(key: "gato")?.category)
    }

    // MARK: grouping and search

    func testGroupingOrdersSectionsAndPutsUnorganizedLast() {
        let env = makeEnvironment().0
        let a = add(env, "uno"), b = add(env, "dos"), c = add(env, "tres"), d = add(env, "cuatro")
        env.repository.updatePlacement(id: a.id, category: "Zeta", tags: [])
        env.repository.updatePlacement(id: b.id, category: "Alfa", tags: [])
        env.repository.updatePlacement(id: c.id, category: "Alfa", tags: [])
        let words = env.repository.allWords()

        let bySize = LibrarySections.group(words, order: .largestFirst, unorganizedTitle: "Not organized yet")
        XCTAssertEqual(bySize.map(\.title), ["Alfa", "Zeta", "Not organized yet"])
        XCTAssertTrue(bySize.last!.isUnorganized)
        XCTAssertEqual(bySize.last!.words.map(\.id), [d.id])

        let alpha = LibrarySections.group(words, order: .alphabetical, unorganizedTitle: "X")
        XCTAssertEqual(alpha.map(\.title), ["Alfa", "Zeta", "X"])
    }

    func testSearchMatchesWordTranslationTagAndCategory() {
        let env = makeEnvironment().0
        let w = add(env, "año")
        env.repository.updatePlacement(id: w.id, category: "Tiempo", tags: ["calendario", "sustantivo"])
        let word = env.repository.find(key: "año")!
        XCTAssertTrue(LibrarySections.matches(word, query: "ano"))
        XCTAssertTrue(LibrarySections.matches(word, query: "meaning of"))
        XCTAssertTrue(LibrarySections.matches(word, query: "calend"))
        XCTAssertTrue(LibrarySections.matches(word, query: "tiempo"))
        XCTAssertTrue(LibrarySections.matches(word, query: "#sustant"))
        XCTAssertFalse(LibrarySections.matches(word, query: "#tiempo"), "'#' searches tags only, not sections")
        XCTAssertFalse(LibrarySections.matches(word, query: "zzz"))
        XCTAssertTrue(LibrarySections.matches(word, query: "  "))
    }

    func testTagCountsSortedByUseThenName() {
        let env = makeEnvironment().0
        let a = add(env, "uno"), b = add(env, "dos")
        env.repository.updatePlacement(id: a.id, category: "C", tags: ["verb", "food"])
        env.repository.updatePlacement(id: b.id, category: "C", tags: ["verb"])
        let counts = LibrarySections.tagCounts(env.repository.allWords())
        XCTAssertEqual(counts.map(\.tag), ["verb", "food"])
        XCTAssertEqual(counts.map(\.count), [2, 1])
    }

    // MARK: organizer

    func testOrganizeAllAppliesPlacementsAndCountsSections() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        add(env, "gato"); add(env, "perro"); add(env, "correr")
        client.organizeWordsResult = .success(OrganizerBatchResult(entries: [
            .init(word: "gato", category: "animals", tags: ["Pet", "noun"]),
            .init(word: "perro", category: "Animals", tags: ["pet"]),
            .init(word: "correr", category: "Actions", tags: ["verb"])
        ]))
        env.organizer.start(scope: .all, environment: env)
        await waitUntilDone(env.organizer)

        XCTAssertEqual(env.organizer.phase, .finished(organized: 3, sections: 2))
        XCTAssertEqual(env.repository.find(key: "gato")?.category, "Animals", "case variants merge into one section")
        XCTAssertEqual(env.repository.find(key: "gato")?.tags, ["pet", "noun"])
        XCTAssertEqual(env.repository.find(key: "correr")?.category, "Actions")
    }

    func testMissingWordsFromAIFallBackToOtherInsteadOfVanishing() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        add(env, "gato"); add(env, "perro")
        client.organizeWordsResult = .success(OrganizerBatchResult(entries: [.init(word: "gato", category: "Animals", tags: ["pet"])]))
        env.organizer.start(scope: .all, environment: env)
        await waitUntilDone(env.organizer)
        XCTAssertEqual(env.repository.find(key: "perro")?.category, "Other")
        XCTAssertEqual(env.repository.allWords().count, 2)
    }

    func testFailureLeavesLibraryUntouched() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        let w = add(env, "gato")
        env.repository.updatePlacement(id: w.id, category: "Keep", tags: ["old"])
        client.organizeWordsResult = .failure(.rateLimited)
        env.organizer.start(scope: .all, environment: env)
        await waitUntilDone(env.organizer)
        XCTAssertEqual(env.organizer.phase, .failed(.rateLimited))
        XCTAssertEqual(env.repository.find(key: "gato")?.category, "Keep")
        XCTAssertEqual(env.repository.find(key: "gato")?.tags, ["old"])
    }

    func testUnorganizedOnlyScopeLeavesExistingWordsAndPassesKnownSections() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        let old = add(env, "gato")
        env.repository.updatePlacement(id: old.id, category: "Animals", tags: ["pet"])
        add(env, "perro")
        client.organizeWordsResult = .success(OrganizerBatchResult(entries: [.init(word: "perro", category: "Animals", tags: ["dog"])]))
        env.organizer.start(scope: .unorganizedOnly, environment: env)
        await waitUntilDone(env.organizer)

        XCTAssertEqual(client.organizeCalls.count, 1)
        XCTAssertEqual(client.organizeCalls[0].words.map(\.word), ["perro"])
        XCTAssertEqual(client.organizeCalls[0].existing, ["Animals"])
        XCTAssertEqual(env.repository.find(key: "gato")?.tags, ["pet"], "already-organized words are not touched")
        XCTAssertEqual(env.repository.find(key: "perro")?.category, "Animals")
    }

    func testLargeLibraryIsSplitIntoBatches() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        for i in 0..<(LibraryOrganizer.batchSize + 5) { add(env, "palabra\(i)") }
        client.organizeWordsResult = .success(OrganizerBatchResult(entries: []))
        env.organizer.start(scope: .all, environment: env)
        await waitUntilDone(env.organizer)
        XCTAssertEqual(client.organizeCalls.count, 2)
        XCTAssertEqual(client.organizeCalls[0].words.count, LibraryOrganizer.batchSize)
        XCTAssertEqual(client.organizeCalls[1].words.count, 5)
    }

    func testMissingKeyFailsImmediately() async {
        let (env, _) = makeEnvironment()
        env.removeAPIKey()
        add(env, "gato")
        env.organizer.start(scope: .all, environment: env)
        await waitUntilDone(env.organizer)
        XCTAssertEqual(env.organizer.phase, .failed(.missingAPIKey))
    }

    // MARK: auto-organize new words

    func testNewWordAutoOrganizeRespectsSettingAndReusesSections() async {
        let (env, client) = makeEnvironment()
        await selectModel(env, client)
        let existing = add(env, "gato")
        env.repository.updatePlacement(id: existing.id, category: "Animals", tags: [])
        let word = add(env, "perro")
        client.organizeWordsResult = .success(OrganizerBatchResult(entries: [.init(word: "perro", category: "animals", tags: ["Dog"])]))

        env.organizerSettings.autoOrganizeNewWords = false
        env.requestOrganizationIfConfigured(for: word)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(client.organizeCalls.isEmpty)
        XCTAssertNil(env.repository.find(key: "perro")?.category)

        env.organizerSettings.autoOrganizeNewWords = true
        env.requestOrganizationIfConfigured(for: word)
        for _ in 0..<100 where env.repository.find(key: "perro")?.category == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(client.organizeCalls.first?.existing, ["Animals"])
        XCTAssertEqual(env.repository.find(key: "perro")?.category, "Animals")
        XCTAssertEqual(env.repository.find(key: "perro")?.tags, ["dog"])
    }

    // MARK: settings

    func testOrganizerSettingsPersistAndTolerateMissingKeys() {
        let defaults = UserDefaults(suiteName: "orgset-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.organizerSettings, .default)
        var custom = OrganizerSettings()
        custom.groupIntoSections = false
        custom.granularity = .detailed
        custom.maxTagsPerWord = 2
        custom.customInstructions = "by topic"
        store.organizerSettings = custom
        XCTAssertEqual(SettingsStore(defaults: defaults).organizerSettings, custom)

        defaults.set(Data(#"{"granularity":"broad"}"#.utf8), forKey: "organizerSettings")
        let partial = SettingsStore(defaults: defaults).organizerSettings
        XCTAssertEqual(partial.granularity, .broad)
        XCTAssertTrue(partial.groupIntoSections, "missing keys fall back to defaults")
    }

    func testOrganizerPromptIncludesExistingSectionsAndLimits() {
        var settings = OrganizerSettings()
        settings.maxTagsPerWord = 3
        settings.customInstructions = "group by topic"
        let prompt = LibraryOrganizerPrompts.systemInstruction(existingCategories: ["Food", "Travel"], settings: settings, language: .arabic)
        XCTAssertTrue(prompt.contains("Food, Travel"))
        XCTAssertTrue(prompt.contains("up to 3 short tags"))
        XCTAssertTrue(prompt.contains("group by topic"))
        XCTAssertTrue(prompt.contains("Arabic"))
        XCTAssertFalse(prompt.contains("\\("), "no un-interpolated placeholders")
    }
}
