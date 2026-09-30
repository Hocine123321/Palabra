import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class PronunciationServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataWordRepository!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        repository = SwiftDataWordRepository(context: ModelContext(container))
        keychain = KeychainStore()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    private func makeEnvironment(ai: AIClient) -> AppEnvironment {
        AppEnvironment(
            ai: ai,
            repository: repository,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "pron-\(UUID().uuidString)") ?? .standard)
        )
    }

    private func sampleContent(word: String = "hablar") -> WordContent {
        WordContent(
            word: word,
            examples: [.init(context: "a", spanish: "uno", english: "one"), .init(context: "b", spanish: "dos", english: "two"), .init(context: "c", spanish: "tres", english: "three")],
            meaning: .init(translations: ["to speak"], explanation: "x"),
            usage: .init(explanation: "x", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: "hablo", note: nil)])]),
            similarWords: [.init(word: "conversar", difference: "x")]
        )
    }

    private let ttsModel = AIModel(id: "models/gemini-2.5-flash-tts", displayName: "Flash TTS", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)

    func testGenerateFailsWithMissingAPIKeyWhenNoneSaved() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        mock.listModelsResult = .success([ttsModel])
        await env.ttsCatalogue.refresh(apiKey: "key", using: mock)
        env.selectedTTSModelID = ttsModel.id
        // Deliberately no saveAPIKey call.

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.pronunciation.status(for: word.id), .failed(.missingAPIKey))
        XCTAssertNil(repository.find(key: "hablar")?.pronunciationAudio)
    }

    func testGenerateFailsWithNoModelSelectedWhenAPIKeyPresentButNoModelChosen() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        // Deliberately no selectedTTSModelID.

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.pronunciation.status(for: word.id), .failed(.noModelSelected))
    }

    func testGenerateFailsWithModelUnavailableWhenSelectionNotInCatalogue() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        env.selectedTTSModelID = "models/stale-tts-model" // never fetched into ttsCatalogue.models

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.pronunciation.status(for: word.id), .failed(.modelUnavailable("models/stale-tts-model")))
    }

    func testGenerateSucceedsAndPersistsAudioWhenFullyConfigured() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        mock.listModelsResult = .success([ttsModel])
        await env.ttsCatalogue.refresh(apiKey: "key", using: mock)
        env.selectedTTSModelID = ttsModel.id

        let audio = WAVAudio.wav(fromPCM: Data([1, 2, 3]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        mock.synthesizeSpeechResult = .success(audio)

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.pronunciation.status(for: word.id), .idle)
        XCTAssertEqual(repository.find(key: "hablar")?.pronunciationAudio, audio)
    }

    func testGenerateSetsFailedStatusAndLeavesNoAudioWhenAICallFails() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        mock.listModelsResult = .success([ttsModel])
        await env.ttsCatalogue.refresh(apiKey: "key", using: mock)
        env.selectedTTSModelID = ttsModel.id
        mock.synthesizeSpeechResult = .failure(.rateLimited)

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.pronunciation.status(for: word.id), .failed(.rateLimited))
        XCTAssertNil(repository.find(key: "hablar")?.pronunciationAudio)
    }

    func testGenerateAutoSelectsDefaultModelWhenNoneChosen() async {
        // e.g. someone who already had an API key before pronunciation existed.
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        mock.listModelsResult = .success([ttsModel])
        let audio = WAVAudio.wav(fromPCM: Data([5, 6]), sampleRate: 24000, channels: 1, bitsPerSample: 16)
        mock.synthesizeSpeechResult = .success(audio)

        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())
        await env.pronunciation.generate(for: word, using: env)

        XCTAssertEqual(env.selectedTTSModelID, ttsModel.id)
        XCTAssertEqual(env.pronunciation.status(for: word.id), .idle)
        XCTAssertEqual(repository.find(key: "hablar")?.pronunciationAudio, audio)
    }

    func testEnsureTTSModelSelectedPicksDefaultFromFetchedCatalogue() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        mock.listModelsResult = .success([
            AIModel(id: "models/gemini-3.8-flash-lite-tts", displayName: "Lite", description: nil, inputTokenLimit: nil, outputTokenLimit: nil),
            AIModel(id: "models/gemini-3.8-flash-tts", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
        ])

        await env.ensureTTSModelSelected()

        XCTAssertEqual(env.selectedTTSModelID, "models/gemini-3.8-flash-tts")
    }

    func testEnsureTTSModelSelectedDoesNotOverrideExistingChoice() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        env.saveAPIKey("AIzaSyExampleKey1234")
        mock.listModelsResult = .success([ttsModel])
        env.selectedTTSModelID = "models/my-own-pick-tts"

        await env.ensureTTSModelSelected()

        XCTAssertEqual(env.selectedTTSModelID, "models/my-own-pick-tts")
    }

    func testEnsureTTSModelSelectedDoesNothingWithoutAPIKey() async {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        mock.listModelsResult = .success([ttsModel])

        await env.ensureTTSModelSelected()

        XCTAssertNil(env.selectedTTSModelID)
    }

    func testRequestPronunciationIfConfiguredDoesNothingWithoutAPIKey() {
        let mock = MockAIClient()
        let env = makeEnvironment(ai: mock)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: sampleContent(), rawJSON: Data())

        env.requestPronunciationIfConfigured(for: word)

        // No API key and no TTS model selected, so this must not even start
        // a request — status stays exactly .idle, synchronously.
        XCTAssertEqual(env.pronunciation.status(for: word.id), .idle)
    }
}
