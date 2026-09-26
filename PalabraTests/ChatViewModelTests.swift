import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class ChatViewModelTests: XCTestCase {
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

    private func content() -> WordContent {
        WordContent(
            word: "hablar",
            examples: [
                .init(context: "a", spanish: "uno", english: "one"),
                .init(context: "b", spanish: "dos", english: "two"),
                .init(context: "c", spanish: "tres", english: "three")
            ],
            meaning: .init(translations: ["to speak"], explanation: "explanation"),
            usage: .init(explanation: "usage", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: "hablo", note: nil)])]),
            similarWords: [.init(word: "conversar", difference: "differs")]
        )
    }

    private func makeEnvironment(client: MockAIClient) -> AppEnvironment {
        let env = AppEnvironment(
            ai: client,
            repository: repository,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "chat-\(UUID().uuidString)") ?? .standard)
        )
        env.saveAPIKey("test-key")
        env.selectedModelID = "models/gemini-2.5-flash"
        return env
    }

    func testSendAppendsUserAndAssistantMessagesAndPersists() async {
        let client = MockAIClient()
        client.sendChatResult = .success("¡Claro!")
        let env = makeEnvironment(client: client)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(), rawJSON: Data())

        let viewModel = ChatViewModel(word: word, environment: env)
        viewModel.draft = "another example please"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(viewModel.messages[1].text, "¡Claro!")
        XCTAssertEqual(repository.find(key: "hablar")?.chat.count, 2)
    }

    func testSendFailureAppendsFailedMessageWithErrorText() async {
        let client = MockAIClient()
        client.sendChatResult = .failure(.rateLimited)
        let env = makeEnvironment(client: client)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(), rawJSON: Data())

        let viewModel = ChatViewModel(word: word, environment: env)
        viewModel.draft = "hi"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.last?.status, .failed)
        XCTAssertEqual(viewModel.messages.last?.errorText, AIError.rateLimited.userMessage)
    }

    func testRetryResendsLastUserMessageAndSucceeds() async {
        let client = MockAIClient()
        client.sendChatResult = .failure(.rateLimited)
        let env = makeEnvironment(client: client)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(), rawJSON: Data())

        let viewModel = ChatViewModel(word: word, environment: env)
        viewModel.draft = "another example please"
        await viewModel.send()
        XCTAssertEqual(viewModel.messages.count, 2)

        client.sendChatResult = .success("Claro, aquí va otro ejemplo.")
        await viewModel.retryLastFailed()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].text, "another example please")
        XCTAssertEqual(viewModel.messages[1].status, .sent)
        XCTAssertEqual(viewModel.messages[1].text, "Claro, aquí va otro ejemplo.")
    }

    func testClearEmptiesMessagesAndPersists() async {
        let client = MockAIClient()
        client.sendChatResult = .success("ok")
        let env = makeEnvironment(client: client)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(), rawJSON: Data())

        let viewModel = ChatViewModel(word: word, environment: env)
        viewModel.draft = "hi"
        await viewModel.send()
        viewModel.clear()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(repository.find(key: "hablar")?.chat.count, 0)
    }

    func testSendIgnoresBlankDraft() async {
        let client = MockAIClient()
        let env = makeEnvironment(client: client)
        let word = repository.insert(spanish: "hablar", key: "hablar", searchKey: "hablar", content: content(), rawJSON: Data())
        let viewModel = ChatViewModel(word: word, environment: env)
        viewModel.draft = "   "
        await viewModel.send()
        XCTAssertTrue(viewModel.messages.isEmpty)
    }
}
