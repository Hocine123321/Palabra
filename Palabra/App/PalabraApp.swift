import SwiftUI
import SwiftData

@MainActor
@main
struct PalabraApp: App {
    let container: ModelContainer
    let environment: AppEnvironment

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("-UITestStub")
        let persist = arguments.contains("-UITestPersist")
        let schema = Schema([Word.self, WordQueueItem.self])

        let configuration: ModelConfiguration = (isUITest && !persist)
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        self.container = container

        if arguments.contains("-UITestReset") {
            let context = ModelContext(container)
            for word in (try? context.fetch(FetchDescriptor<Word>())) ?? [] {
                context.delete(word)
            }
            try? context.save()
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
            let env = AppEnvironment(
                ai: StubAIClient(),
                repository: SwiftDataWordRepository(context: ModelContext(container)),
                catalogue: catalogue,
                ttsCatalogue: ttsCatalogue,
                keychain: keychain,
                settings: settings,
                wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container))
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
        }
    }
}
