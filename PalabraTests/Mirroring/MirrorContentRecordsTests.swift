import SwiftData
import XCTest
@testable import Palabra

@MainActor
final class MirrorContentRecordsTests: XCTestCase {
    private var words: SwiftDataWordRepository!
    private var artifacts: SwiftDataArtifactRepository!
    private var chats: SwiftDataChatRepository!
    private var env: AppEnvironment!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let markup = "<img src=x onerror=1>"

    override func setUpWithError() throws {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        words = SwiftDataWordRepository(context: ModelContext(container))
        artifacts = SwiftDataArtifactRepository.inMemory()
        chats = SwiftDataChatRepository.inMemory()
        env = AppEnvironment(
            ai: MockAIClient(),
            repository: words,
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(account: "mirror-content-\(UUID().uuidString)"),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "mirror-content-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            artifactRepository: artifacts,
            chatRepository: chats
        )
    }

    private func collection(_ kind: String) async throws -> MirrorCollection {
        let all = await env.mirrorContentCollections()
        return try XCTUnwrap(all.first { $0.kind == kind }, kind)
    }

    @discardableResult
    private func addSpec(_ json: String, title: String = "Plan", requested: [String] = ["library.words"]) -> Artifact {
        guard case .success(let artifact) = artifacts.create(title: title, kind: .spec, payload: Data(json.utf8), requested: requested, prompt: "", now: now) else {
            fatalError("create failed")
        }
        return artifact
    }

    func testBothKindsAreBuiltEvenWhenEmpty() async throws {
        let collections = await env.mirrorContentCollections()
        XCTAssertEqual(collections.map(\.kind), ["artifact", "chat"])
        XCTAssertEqual(collections[0].records, [])
        XCTAssertEqual(collections[1].records, [])
    }

    func testABoundTableIsResolvedAndAChartWithInlineDataIsUnchanged() async throws {
        _ = words.insert(spanish: "hola", key: "hola", searchKey: "hola", content: StubAIClient.sampleContent(for: "hola"), rawJSON: Data())
        let spec = """
        {"blocks":[
          {"type":"heading","level":1,"text":"\(markup)"},
          {"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{"limit":10}}},
          {"type":"chart","style":"bar","title":"Words","labels":["Mon","Tue"],"series":[{"name":"Words","values":[3,5]}]},
          {"type":"section","title":"Inner","children":[{"type":"text","text":"hi"},{"type":"table","columns":[{"title":"A"}],"rows":[["x"]]}]}
        ]}
        """
        let artifact = addSpec(spec, title: markup)
        let artifactRecords = try await collection("artifact").records
        let record = try XCTUnwrap(artifactRecords.first)
        XCTAssertEqual(record.recordID, artifact.id.uuidString)
        let payload = try XCTUnwrap(record.payload.objectValue)
        XCTAssertEqual(Set(payload.keys), ["id", "title", "kind", "version", "updatedAt", "blocks"])
        XCTAssertEqual(payload["title"]?.stringValue, markup)
        XCTAssertEqual(payload["kind"]?.stringValue, "spec")
        let blocks = try XCTUnwrap(payload["blocks"]?.arrayValue)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0]["text"]?.stringValue, markup)
        // the bind became inline rows and no longer mentions the capability
        XCTAssertEqual(blocks[1]["type"]?.stringValue, "table")
        XCTAssertEqual(blocks[1]["rows"]?.arrayValue, [.array([.string("hola")])])
        XCTAssertNil(blocks[1]["bind"])
        XCTAssertEqual(blocks[2]["type"]?.stringValue, "chart")
        XCTAssertEqual(blocks[2]["labels"]?.arrayValue, [.string("Mon"), .string("Tue")])
        XCTAssertEqual(blocks[2]["series"]?.arrayValue?.first?["values"]?.arrayValue, [.number(3), .number(5)])
        // nested blocks are resolved too
        let children = try XCTUnwrap(blocks[3]["children"]?.arrayValue)
        XCTAssertEqual(children[1]["rows"]?.arrayValue, [.array([.string("x")])])
    }

    func testAFailedBindBecomesAnErrorBlockAndTheRestStays() async throws {
        addSpec("""
        {"blocks":[{"type":"text","text":"before"},
          {"type":"table","columns":[{"title":"W","field":"w"}],"bind":{"capability":"no.such.capability"}},
          {"type":"text","text":"after"}]}
        """)
        let artifactRecords = try await collection("artifact").records
        let record = try XCTUnwrap(artifactRecords.first)
        let blocks = try XCTUnwrap(record.payload["blocks"]?.arrayValue)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["text"]?.stringValue, "before")
        XCTAssertEqual(blocks[1]["type"]?.stringValue, "error")
        XCTAssertEqual(blocks[1]["message"]?.stringValue, "Couldn't load data")
        XCTAssertEqual(blocks[2]["text"]?.stringValue, "after")
    }

    func testAnAppIsListedWithoutItsPageAndAnUndecodableSpecIsLeftOut() async throws {
        let secret = "<html>SECRET-PAGE-SOURCE</html>"
        guard case .success(let app) = artifacts.create(title: "Game", kind: .app, payload: Data(secret.utf8), requested: [], prompt: "", now: now) else { return XCTFail() }
        addSpec("this is not json", title: "Broken")
        let good = addSpec(#"{"blocks":[{"type":"text","text":"ok"}]}"#, title: "Good")

        let records = try await collection("artifact").records
        XCTAssertEqual(Set(records.map(\.recordID)), [app.id.uuidString, good.id.uuidString], "the broken spec is not mirrored")
        let appRecord = try XCTUnwrap(records.first { $0.recordID == app.id.uuidString })
        XCTAssertEqual(appRecord.payload["blocks"], JSONValue.null)
        XCTAssertEqual(appRecord.payload["kind"]?.stringValue, "app")
        for record in records { XCTAssertFalse(record.payload.jsonString.contains("SECRET-PAGE-SOURCE")) }
    }

    func testOnlyTheLatestChatIsMirroredWithoutThumbnailsActionsOrErrors() async throws {
        let old = chats.create(title: "Old", wordID: nil, turns: [ChatTurn(role: .user, text: "old")], now: now.addingTimeInterval(-100))
        let turns = [
            ChatTurn(role: .user, text: markup, createdAt: now, thumbnail: Data([1, 2, 3])),
            ChatTurn(role: .assistant, text: "مرحبا", createdAt: now, status: .failed, errorText: "SECRET-ERROR",
                     actions: [ChatAction(capability: "words.add", argsJSON: "{}", summary: "SECRET-ACTION", isWrite: true, state: .pending)]),
        ]
        let wordID = UUID()
        let latest = chats.create(title: "Latest", wordID: wordID, turns: turns, now: now)

        let records = try await collection("chat").records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].recordID, "latest")
        let payload = try XCTUnwrap(records[0].payload.objectValue)
        XCTAssertEqual(Set(payload.keys), ["id", "title", "wordId", "updatedAt", "turns"])
        XCTAssertEqual(payload["id"]?.stringValue, latest.id.uuidString)
        XCTAssertNotEqual(payload["id"]?.stringValue, old.id.uuidString)
        XCTAssertEqual(payload["wordId"]?.stringValue, wordID.uuidString)
        let mirrored = try XCTUnwrap(payload["turns"]?.arrayValue)
        XCTAssertEqual(mirrored.count, 2)
        XCTAssertEqual(Set(try XCTUnwrap(mirrored[0].objectValue).keys), ["role", "text", "createdAt", "status"])
        XCTAssertEqual(mirrored[0]["text"]?.stringValue, markup)
        XCTAssertEqual(mirrored[1]["role"]?.stringValue, "assistant")
        XCTAssertEqual(mirrored[1]["text"]?.stringValue, "مرحبا")
        XCTAssertEqual(mirrored[1]["status"]?.stringValue, "failed")
        let text = records[0].payload.jsonString
        XCTAssertFalse(text.contains("SECRET-ERROR") || text.contains("SECRET-ACTION"))
    }

    func testAVeryLongChatKeepsTheNewestTurnsWithinTheBudget() async throws {
        let long = String(repeating: "a", count: 8_000)
        let turns = (0..<40).map { ChatTurn(role: $0 % 2 == 0 ? .user : .assistant, text: "\($0) " + long, createdAt: now) }
        chats.create(title: "Big", wordID: nil, turns: turns, now: now)
        let chatRecords = try await collection("chat").records
        let record = try XCTUnwrap(chatRecords.first)
        let mirrored = try XCTUnwrap(record.payload["turns"]?.arrayValue)
        XCTAssertLessThan(mirrored.count, 40)
        XCTAssertGreaterThan(mirrored.count, 10)
        XCTAssertTrue(try XCTUnwrap(mirrored.last?["text"]?.stringValue).hasPrefix("39 "), "the newest turn is kept")
        XCTAssertLessThan(record.payload.jsonString.count, 200_000)
    }
}
