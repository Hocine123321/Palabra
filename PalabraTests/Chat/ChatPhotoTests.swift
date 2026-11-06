import SwiftData
import UIKit
import XCTest
@testable import Palabra

/// A photo of a book page goes to Gemini with the message: these check what is actually sent, not just that a call happened.
@MainActor
final class ChatPhotoTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        keychain = KeychainStore()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    private func makeEnvironment() async -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "chatphoto-\(UUID().uuidString)") ?? .standard),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            chatRepository: SwiftDataChatRepository.inMemory()
        )
        env.saveAPIKey("test-api-key")
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
        return (env, client)
    }

    private func jpeg(side: CGFloat = 600) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func makeSession(_ env: AppEnvironment) throws -> ChatSession {
        let conversation = env.chat.create(title: ChatConversation.defaultTitle, wordID: nil, turns: [], now: Date())
        return try XCTUnwrap(env.makeChatSession(conversationID: conversation.id))
    }

    func testPhotoIsSentWithTheMessageAndKeptAsAThumbnail() async throws {
        let (env, client) = await makeEnvironment()
        client.imageResult = .success("I found *hola* and *adiós*.")
        let session = try makeSession(env)
        XCTAssertTrue(session.canAttachPhotos)
        await session.attachPhoto(jpeg())
        XCTAssertNotNil(session.attachment)
        await session.send()
        XCTAssertNil(session.attachment)
        XCTAssertEqual(client.imageCalls.count, 1)
        let call = try XCTUnwrap(client.imageCalls.first)
        XCTAssertEqual(call.image.mimeType, "image/jpeg")
        XCTAssertGreaterThan(call.image.data.count, 500)
        XCTAssertTrue(call.prompt.contains("[photo attached]"), call.prompt)
        XCTAssertTrue(call.systemInstruction.contains("photo"), "the model is told how to treat the photo")
        XCTAssertTrue(client.generateJSONCalls.isEmpty, "a message with a photo does not also go out as plain text")
        let user = try XCTUnwrap(session.turns.first)
        XCTAssertEqual(user.text, "")
        let thumbnail = try XCTUnwrap(user.thumbnail)
        XCTAssertLessThan(thumbnail.count, 80_000)
        XCTAssertEqual(session.title, "Photo")
        XCTAssertEqual(session.turns.last?.text, "I found *hola* and *adiós*.")
    }

    func testFollowUpStillSeesThePhoto() async throws {
        let (env, client) = await makeEnvironment()
        client.imageResult = .success("Found three words.")
        let session = try makeSession(env)
        await session.attachPhoto(jpeg())
        await session.send()
        session.draft = "add the first two"
        await session.send()
        XCTAssertEqual(client.imageCalls.count, 2)
        XCTAssertTrue(client.imageCalls[1].prompt.contains("add the first two"))
        XCTAssertEqual(client.imageCalls[1].image, client.imageCalls[0].image)
    }

    func testTextOnlyMessagesStayPlain() async throws {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success("Hola!")
        let session = try makeSession(env)
        session.draft = "hello"
        await session.send()
        XCTAssertTrue(client.imageCalls.isEmpty)
        XCTAssertEqual(client.generateJSONCalls.count, 1)
        XCTAssertFalse(client.generateJSONCalls[0].systemInstruction.contains("latest photo"))
    }

    func testUnreadablePhotoIsReportedAndNothingIsAttached() async throws {
        let (env, _) = await makeEnvironment()
        let session = try makeSession(env)
        await session.attachPhoto(Data([0, 1, 2, 3]))
        XCTAssertNil(session.attachment)
        XCTAssertEqual(session.attachmentProblem, "That photo could not be read.")
        session.removeAttachment()
        XCTAssertNil(session.attachmentProblem)
    }

    func testPhotoOnlyNeedsNoText() async throws {
        let (env, client) = await makeEnvironment()
        client.imageResult = .success("Nothing readable here.")
        let session = try makeSession(env)
        XCTAssertTrue(session.draft.isEmpty)
        await session.send()
        XCTAssertTrue(session.turns.isEmpty, "no text and no photo sends nothing")
        await session.attachPhoto(jpeg())
        await session.send()
        XCTAssertEqual(session.turns.count, 2)
    }

    func testThumbnailSurvivesSavingAndOldTurnsStillDecode() throws {
        let turn = ChatTurn(role: .user, text: "x", thumbnail: Data([9, 9]))
        let back = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn))
        XCTAssertEqual(back.thumbnail, Data([9, 9]))
        let old = Data(#"{"role":"user","text":"hi"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ChatTurn.self, from: old).thumbnail)
    }
}
