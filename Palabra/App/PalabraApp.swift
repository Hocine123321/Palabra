import SwiftUI
import SwiftData

@MainActor
@main
struct PalabraApp: App {
    let container: ModelContainer
    let environment: AppEnvironment
    /// True when the library on disk could not be opened and the app runs on a temporary in-memory one.
    @State private var showStoreProblem: Bool

    /// The UI-test launch arguments only exist in Debug builds. `-UITestReset` wipes the library and `-UITestStub`
    /// replaces the AI and overwrites the saved API key, so a build that people install must ignore them.
    private static let launchArguments: [String] = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments
        #else
        return []
        #endif
    }()

    init() {
        let arguments = Self.launchArguments
        let isUITest = arguments.contains("-UITestStub")
        let persist = arguments.contains("-UITestPersist")
        let schema = Schema([Word.self, WordQueueItem.self, Deck.self, Card.self, ReviewLog.self, Artifact.self, ArtifactVersion.self, ArtifactStateEntry.self, ReviewNeed.self, ChatConversation.self, SolveEntry.self])

        let configuration: ModelConfiguration = (isUITest && !persist)
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema)
        let container: ModelContainer
        var storeFailed = false
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that can't be opened must not crash the app on every launch. Run on a temporary in-memory
            // store instead; the files on disk are left untouched. The person is told (see `body`), because
            // anything saved from now on is lost when the app closes.
            storeFailed = true
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        self.container = container
        _showStoreProblem = State(initialValue: storeFailed)

        if arguments.contains("-UITestReset") {
            let context = ModelContext(container)
            for word in (try? context.fetch(FetchDescriptor<Word>())) ?? [] {
                context.delete(word)
            }
            for deck in (try? context.fetch(FetchDescriptor<Deck>())) ?? [] { context.delete(deck) }
            for card in (try? context.fetch(FetchDescriptor<Card>())) ?? [] { context.delete(card) }
            for log in (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? [] { context.delete(log) }
            for artifact in (try? context.fetch(FetchDescriptor<Artifact>())) ?? [] { context.delete(artifact) }
            for version in (try? context.fetch(FetchDescriptor<ArtifactVersion>())) ?? [] { context.delete(version) }
            for entry in (try? context.fetch(FetchDescriptor<ArtifactStateEntry>())) ?? [] { context.delete(entry) }
            for need in (try? context.fetch(FetchDescriptor<ReviewNeed>())) ?? [] { context.delete(need) }
            for conversation in (try? context.fetch(FetchDescriptor<ChatConversation>())) ?? [] { context.delete(conversation) }
            for entry in (try? context.fetch(FetchDescriptor<SolveEntry>())) ?? [] { context.delete(entry) }
            Persistence.save(context)
        }

        if isUITest {
            let settings = SettingsStore(defaults: UserDefaults(suiteName: "uitest-\(UUID().uuidString)") ?? .standard)
            let keychain = KeychainStore()
            if arguments.contains("-UITestNoKey") {
                keychain.delete()
            } else {
                keychain.save("uitest-stub-key")
            }
            settings.hasCompletedOnboarding = !arguments.contains("-UITestOnboarding")

            let catalogue = ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let ttsCatalogue = ModelCatalogue(
                cacheFileName: "TTSModelCatalogue.json",
                filter: TTSModelFilter.apply,
                cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
            // Solve: canned answers, and a fake App ID unless `-UITestNoSolveKey`.
            let solveKeychain = KeychainStore(account: "wolfram-app-id-uitest")
            if arguments.contains("-UITestNoSolveKey") { solveKeychain.delete() } else { solveKeychain.save("uitest-wolfram") }
            let solveTool = SolveTool(
                solver: StubMathSolver(),
                recognizer: StubTextRecognizer(),
                history: SwiftDataSolveRepository(context: ModelContext(container)),
                usage: SolveUsage(defaults: UserDefaults(suiteName: "uitest-solve-\(UUID().uuidString)") ?? .standard),
                keychain: solveKeychain
            )
            let env = AppEnvironment(
                ai: StubAIClient(),
                repository: SwiftDataWordRepository(context: ModelContext(container)),
                catalogue: catalogue,
                ttsCatalogue: ttsCatalogue,
                keychain: keychain,
                settings: settings,
                wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
                cardRepository: SwiftDataCardRepository(context: ModelContext(container)),
                artifactRepository: SwiftDataArtifactRepository(context: ModelContext(container)),
                reviewRepository: SwiftDataReviewRepository(context: ModelContext(container)),
                chatRepository: SwiftDataChatRepository(context: ModelContext(container)),
                solveTool: solveTool
            )
            if !arguments.contains("-UITestNoKey") {
                env.selectedModelID = StubAIClient.sampleModels.first?.id
                env.selectedTTSModelID = StubAIClient.sampleModels.last?.id
                // A selected ID only resolves to a model once its catalogue is
                // populated, so load both from the stub (a ~0.2s delay).
                Task {
                    await env.catalogue.refresh(apiKey: "uitest-stub-key", using: env.ai)
                    await env.ttsCatalogue.refresh(apiKey: "uitest-stub-key", using: env.ai)
                }
            }
            if let seedIndex = arguments.firstIndex(of: "-UITestSeed"),
               seedIndex + 1 < arguments.count,
               let count = Int(arguments[seedIndex + 1]) {
                for i in 0..<count {
                    let word = "palabra\(i)"
                    env.repository.insert(
                        spanish: word,
                        key: WordKey.identity(word),
                        searchKey: WordKey.search(word),
                        content: StubAIClient.sampleContent(for: word),
                        rawJSON: Data()
                    )
                }
                env.syncVocabularyCards()
                // `-UITestSeedReview` flags the first seeded word so Need Review has something to show.
                if arguments.contains("-UITestSeedReview"), let word = env.repository.find(key: WordKey.identity("palabra0")) {
                    env.review.flag([ReviewFlag(wordID: word.id, headword: word.spanish, translation: word.translation, score: 0.8, note: "Seeded note", sourceArtifactID: nil)], now: Date())
                }
            }
            environment = env
        } else {
            environment = AppEnvironment.live(modelContext: ModelContext(container))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(container)
                .alert("Your library couldn't be opened", isPresented: $showStoreProblem) {
                    Button("Close", role: .cancel) {}
                } message: {
                    Text("Palabra is using a temporary library, so anything you add will be lost when the app closes. Close the app and open it again. If this keeps happening, don't delete the app: your saved words are still on this device.")
                }
        }
    }
}
