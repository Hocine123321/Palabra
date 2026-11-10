import SwiftData
import XCTest
@testable import Palabra

@MainActor
final class MirrorBooksRecordsTests: XCTestCase {
    private func makeEnv(_ shelf: BookShelf) throws -> AppEnvironment {
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppEnvironment(
            ai: MockAIClient(),
            repository: SwiftDataWordRepository(context: ModelContext(container)),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: KeychainStore(account: "mirror-books-\(UUID().uuidString)"),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "mirror-books-\(UUID().uuidString)")!),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container)),
            bookShelf: shelf
        )
    }

    private func fixtureShelf() -> BookShelf {
        BookShelf.inMemory(source: StubBookSource(
            catalogue: BookFixtures.catalogue,
            lessons: ["lesson-empires": BookFixtures.empires, "lesson-revolutions": BookFixtures.revolutions, "lesson-rivers": BookFixtures.rivers]
        ))
    }

    private func collection(_ env: AppEnvironment, _ kind: String) throws -> MirrorCollection {
        try XCTUnwrap(env.mirrorBooksCollections().first { $0.kind == kind }, kind)
    }

    func testLessonsAndPagesBecomeRecordsInBookOrder() throws {
        let env = try makeEnv(fixtureShelf())
        let lessons = try collection(env, "lesson").records
        let pages = try collection(env, "lessonPage").records
        XCTAssertEqual(Set(lessons.map(\.recordID)), ["empires", "revolutions", "rivers"])
        XCTAssertEqual(lessons.count, 3)

        let empires = try XCTUnwrap(lessons.first { $0.recordID == "empires" })
        let payload = try XCTUnwrap(empires.payload.objectValue)
        XCTAssertEqual(Set(payload.keys), ["id", "version", "title", "summary", "bookId", "bookTitle", "chapterId", "chapterTitle", "language", "pageIds", "terms", "notes"])
        XCTAssertEqual(payload["bookId"]?.stringValue, "history")
        XCTAssertEqual(payload["chapterTitle"]?.stringValue, "Unit 1")
        XCTAssertEqual(payload["language"]?.stringValue, "en")
        XCTAssertEqual(payload["pageIds"]?.arrayValue, [.string("p1"), .string("p2")])
        XCTAssertEqual(payload["terms"]?["markets"]?["term"]?.stringValue, "Markets", "a definition card with an id is a term")

        // pages: numbered in book order, one record each, keyed "<lessonId>/<pageId>"
        let history = pages.filter { $0.payload["lessonId"]?.stringValue != "rivers" }
        XCTAssertEqual(history.map(\.recordID), ["empires/p1", "empires/p2", "revolutions/p1"])
        XCTAssertEqual(history.compactMap { $0.payload["number"]?.intValue }, [1, 2, 3])
        let first = try XCTUnwrap(history.first?.payload.objectValue)
        XCTAssertEqual(Set(first.keys), ["lessonId", "id", "number", "title", "dateLabel", "blocks"])
        XCTAssertEqual(first["id"]?.stringValue, "p1")
        XCTAssertEqual(first["blocks"]?.arrayValue?.first?["type"]?.stringValue, "paragraph")
    }

    func testAnImageShipsOnlyAltAndCaptionAndUnknownBlocksKeepTheirType() throws {
        let hostile = "<img src=x onerror=1>"
        let long = String(repeating: "ب", count: 3_000)
        let lesson = """
        {"id":"odd","title":"Odd","pages":[{"id":"p1","title":"\(hostile)","blocks":[
          {"type":"image","image":"secret-asset-name","caption":"Cap","alt":"Alt","style":"map"},
          {"type":"image","image":"other","alt":"Only alt"},
          {"type":"hologram"},
          {"type":"paragraph","text":"\(long) 😀 \(hostile)"}
        ]}]}
        """
        let catalogue = #"{"books":[{"id":"b","subject":"history","title":"B","language":"ar","chapters":[{"id":"c","title":"C","lessons":[{"id":"odd","file":"lesson-odd"}]}]}]}"#
        let env = try makeEnv(BookShelf.inMemory(source: StubBookSource(catalogue: catalogue, lessons: ["lesson-odd": lesson])))
        let page = try XCTUnwrap(try collection(env, "lessonPage").records.first)
        XCTAssertEqual(page.payload["title"]?.stringValue, hostile)
        let blocks = try XCTUnwrap(page.payload["blocks"]?.arrayValue)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(Set(try XCTUnwrap(blocks[0].objectValue).keys), ["type", "alt", "caption"])
        XCTAssertEqual(Set(try XCTUnwrap(blocks[1].objectValue).keys), ["type", "alt"])
        XCTAssertFalse(page.payload.jsonString.contains("secret-asset-name"))
        XCTAssertEqual(blocks[2]["type"]?.stringValue, "hologram")
        XCTAssertEqual(blocks[3]["text"]?.stringValue, "\(long) 😀 \(hostile)", "Arabic, emoji and markup survive byte for byte")
    }

    func testADeletedLessonDropsOutOfTheNextBuild() throws {
        let shelf = BookShelf.inMemory()
        let env = try makeEnv(shelf)
        let before = try collection(env, "lesson").records
        let victim = try XCTUnwrap(before.first?.recordID)
        let pagesBefore = try collection(env, "lessonPage").records.filter { $0.payload["lessonId"]?.stringValue == victim }
        XCTAssertFalse(pagesBefore.isEmpty)

        try shelf.deleteLesson(id: victim)

        XCTAssertFalse(try collection(env, "lesson").records.contains { $0.recordID == victim })
        XCTAssertFalse(try collection(env, "lessonPage").records.contains { $0.payload["lessonId"]?.stringValue == victim })
    }

    func testEveryBundledPageFitsInOneItemOnceSealed() throws {
        let env = try makeEnv(BookShelf.inMemory(source: BundleBookSource()))
        let keys = try XCTUnwrap(MirrorKeys(dataKey: Data(repeating: 7, count: 32)))
        var largest = 0
        for collection in env.mirrorBooksCollections() {
            for record in collection.records {
                let envelope: JSONValue = .object([
                    "v": .number(1), "k": .string(record.kind), "r": .string(record.recordID),
                    "h": .string(record.contentHash), "g": .number(1_800_000_000), "d": record.payload,
                ])
                let id = MirrorCrypto.itemID(keys: keys, kind: record.kind, recordID: record.recordID)
                let sealed = try MirrorCrypto.sealItem(keys: keys, itemID: id, plaintext: Data(envelope.jsonString.utf8))
                largest = max(largest, Base64URL.encode(sealed).count)
            }
        }
        XCTAssertGreaterThan(largest, 0, "the bundle has lessons")
        XCTAssertLessThan(largest, MirrorPusher.maxSealedChars)
    }
}
