import SwiftData
import UIKit
import XCTest
@testable import Palabra

@MainActor
final class LessonStudioSessionTests: XCTestCase {
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

    private func makeEnvironment(withKey: Bool = true) async -> (AppEnvironment, MockAIClient) {
        let client = MockAIClient()
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "studio-\(UUID().uuidString)") ?? .standard),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            bookShelf: BookShelf.inMemory()
        )
        guard withKey else { return (env, client) }
        env.saveAPIKey("test-api-key")
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        await env.catalogue.refresh(apiKey: "test-api-key", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
        return (env, client)
    }

    private func photoData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func lessonReply(text: String = "It began in 1830.") -> String {
        #"{"title":"Colonial movement","pages":[{"title":"Start","blocks":[{"type":"paragraph","text":"\#(text)"}]}]}"#
    }

    func testPhotosAreReadInOrderAndAppendedToTheTextThenTheTextIsEditableBeforeFormatting() async {
        let (env, client) = await makeEnvironment()
        client.imageResult = .success(#"{"text":"page one text 1830","uncertain":["a word"]}"#)
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "typed first"
        await session.attachPhoto(photoData())
        await session.attachPhoto(photoData())
        XCTAssertEqual(session.photos.count, 2)
        await session.transcribe()
        XCTAssertEqual(client.imageCalls.count, 2)
        XCTAssertEqual(session.stage, .rawText)
        XCTAssertTrue(session.rawText.hasPrefix("typed first\n\npage one text 1830"))
        XCTAssertEqual(session.uncertain, ["1: a word", "2: a word"])
        XCTAssertTrue(session.photos.isEmpty)
    }

    func testTypedTextSkipsTranscriptionAndFormatsADraft() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(lessonReply())
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "It began in 1830."
        await session.formatDraft()
        XCTAssertEqual(session.stage, .draft)
        XCTAssertEqual(session.draft?.lesson.title, "Colonial movement")
        XCTAssertTrue(client.imageCalls.isEmpty)
    }

    func testFormattingNeedsText() async {
        let (env, client) = await makeEnvironment()
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "   "
        await session.formatDraft()
        XCTAssertEqual(session.stage, .input)
        XCTAssertTrue(client.generateJSONCalls.isEmpty)
    }

    func testReviseReplacesTheDraftOnlyOnSuccess() async {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(lessonReply())
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "It began in 1830."
        await session.formatDraft()
        let before = session.draft
        client.generateJSONScript = [.failure(.offline)]
        await session.revise("make it a list")
        XCTAssertEqual(session.draft, before)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertTrue(session.changes.isEmpty)
        client.generateJSONResult = .success(lessonReply(text: "It began in 1830 and more."))
        await session.revise("add a paragraph")
        XCTAssertNotEqual(session.draft, before)
        XCTAssertEqual(session.changes, ["add a paragraph"])
    }

    func testSaveWritesTheLessonIntoTheChosenChapterAndBumpsTheLibraryVersion() async throws {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(lessonReply())
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "It began in 1830."
        await session.formatDraft()
        let before = env.books.libraryVersion
        let id = try session.save()
        XCTAssertEqual(id, "colonial-movement-2") // the bundled history lesson already has the id "colonial-movement"
        XCTAssertEqual(env.books.libraryVersion, before + 1)
        XCTAssertNotNil(env.books.book(id: "history")?.firstPageIndex(ofLesson: id))
    }

    func testSaveIntoANewChapter() async throws {
        let (env, client) = await makeEnvironment()
        client.generateJSONResult = .success(lessonReply())
        let session = LessonStudioSession(environment: env, bookID: "geography")
        XCTAssertNil(session.chapterID) // the geography book has no chapters yet
        session.newChapterTitle = "Unit 1"
        session.rawText = "It began in 1830."
        await session.formatDraft()
        let id = try session.save()
        let book = try XCTUnwrap(env.books.book(id: "geography"))
        XCTAssertEqual(book.chapters.map(\.title), ["Unit 1"])
        XCTAssertNotNil(book.firstPageIndex(ofLesson: id))
    }

    func testNoAPIKeyMakesNoAICall() async {
        let (env, client) = await makeEnvironment(withKey: false)
        let session = LessonStudioSession(environment: env, bookID: "history")
        session.rawText = "text"
        await session.formatDraft()
        XCTAssertEqual(session.stage, .input)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertTrue(client.generateJSONCalls.isEmpty)
    }
}
