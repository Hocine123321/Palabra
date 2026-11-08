import SwiftData
import XCTest
@testable import Palabra

@MainActor
final class MirrorWordRecordsTests: XCTestCase {
    private var words: SwiftDataWordRepository!
    private var env: AppEnvironment!

    override func setUpWithError() throws {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        words = SwiftDataWordRepository(context: ModelContext(container))
        env = AppEnvironment(
            ai: MockAIClient(),
            repository: words,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(account: "mirror-words-\(UUID().uuidString)"),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "mirror-words-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            reviewRepository: SwiftDataReviewRepository.inMemory()
        )
    }

    private func add(_ spanish: String) -> Word {
        words.insert(spanish: spanish, key: spanish, searchKey: spanish, content: StubAIClient.sampleContent(for: spanish), rawJSON: Data("raw".utf8))
    }

    func testAnEmptyLibraryGivesNoRecords() {
        XCTAssertEqual(env.mirrorWordRecords(), [])
    }

    func testWordsBecomeRecordsWithoutAudioChatOrRawJSON() throws {
        let hola = add("hola")
        hola.category = "Greetings"
        hola.tags = ["saludo", "basic"]
        hola.pronunciationAudio = Data(repeating: 1, count: 10)
        let adios = add("adios")
        adios.category = "Farewells"

        let records = env.mirrorWordRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.kind == "word" })
        let record = try XCTUnwrap(records.first { $0.recordID == hola.id.uuidString })
        let payload = try XCTUnwrap(record.payload.objectValue)
        XCTAssertEqual(payload["spanish"]?.stringValue, "hola")
        XCTAssertEqual(payload["translation"]?.stringValue, "(sample translation)")
        XCTAssertEqual(payload["category"]?.stringValue, "Greetings")
        XCTAssertEqual(payload["tags"]?.arrayValue?.compactMap(\.stringValue), ["saludo", "basic"])
        XCTAssertEqual(payload["content"]?["examples"]?.arrayValue?.count, 3)
        for forbidden in ["pronunciationAudio", "chatData", "rawJSON"] {
            XCTAssertNil(payload[forbidden], forbidden)
        }
        let other = try XCTUnwrap(records.first { $0.recordID == adios.id.uuidString })
        XCTAssertEqual(other.payload["category"]?.stringValue, "Farewells")
        XCTAssertEqual(other.payload["tags"]?.arrayValue?.count, 0)
    }
}
