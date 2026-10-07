import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class CapabilityProvidersTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var words: SwiftDataWordRepository!
    private var artifacts: SwiftDataArtifactRepository!
    private var registry: CapabilityRegistry!

    private let iso = ISO8601DateFormatter()
    private lazy var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()
    private var now: Date { iso.date(from: "2026-10-07T12:00:00Z")! } // a Wednesday
    private let session = ArtifactSession(artifactID: UUID(), dryRun: false)
    private let everything: Set<String> = ["library.words", "library.word", "stats.wordsPerDay", "stats.wordsPerWeek"]

    override func setUp() {
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        words = SwiftDataWordRepository(context: context)
        artifacts = SwiftDataArtifactRepository.inMemory()
        let fixedNow = now
        registry = CapabilityProviders.registry(words: words, artifacts: artifacts, calendar: utc, now: { fixedNow })
    }

    @discardableResult
    private func addWord(_ spanish: String, at created: String, category: String? = nil, tags: [String] = []) -> Word {
        let key = WordKey.identity(spanish)
        let word = Word(spanish: spanish, key: key, searchKey: WordKey.search(spanish), content: StubAIClient.sampleContent(for: spanish), rawJSON: Data(), createdAt: iso.date(from: created)!)
        word.pronunciationAudio = Data([1, 2, 3])
        word.category = category
        word.tags = tags
        context.insert(word)
        try? context.save()
        return word
    }

    private func call(_ name: String, _ args: JSONValue = .object([:]), session: ArtifactSession? = nil, granted: Set<String>? = nil) async -> Result<JSONValue, CapabilityError> {
        await registry.call(name: name, args: args, session: session ?? self.session, granted: granted ?? everything)
    }

    private func array(_ result: Result<JSONValue, CapabilityError>, file: StaticString = #filePath, line: UInt = #line) -> [JSONValue] {
        guard case .success(.array(let items)) = result else {
            XCTFail("expected an array, got \(result)", file: file, line: line)
            return []
        }
        return items
    }

    // MARK: registry shape

    func testRegistryNamesAreUniqueAndComplete() {
        XCTAssertEqual(
            registry.all.map(\.name),
            ["library.word", "library.words", "stats.wordsPerDay", "stats.wordsPerWeek", "storage.get", "storage.remove", "storage.set"]
        )
        XCTAssertEqual(registry.capability(named: "storage.get")?.kind, .local)
        XCTAssertEqual(registry.capability(named: "library.words")?.kind, .read)
    }

    // MARK: library.words

    func testLibraryWordsNewestFirstAndPaged() async {
        addWord("uno", at: "2026-10-01T10:00:00Z")
        addWord("dos", at: "2026-10-02T10:00:00Z")
        addWord("tres", at: "2026-10-03T10:00:00Z")
        let all = array(await call("library.words"))
        XCTAssertEqual(all.compactMap { $0["spanish"]?.stringValue }, ["tres", "dos", "uno"])
        let page = array(await call("library.words", .object(["limit": .number(1), "offset": .number(1)])))
        XCTAssertEqual(page.compactMap { $0["spanish"]?.stringValue }, ["dos"])
    }

    func testLibraryWordsItemShapeOmitsAudioAndChat() async {
        addWord("hablar", at: "2026-10-01T10:00:00Z", category: "Daily life", tags: ["verb"])
        let item = array(await call("library.words")).first
        XCTAssertEqual(item?["spanish"]?.stringValue, "hablar")
        XCTAssertEqual(item?["key"]?.stringValue, "hablar")
        XCTAssertEqual(item?["translation"]?.stringValue, "(sample translation)")
        XCTAssertEqual(item?["partOfSpeech"]?.stringValue, "noun")
        XCTAssertEqual(item?["category"]?.stringValue, "Daily life")
        XCTAssertEqual(item?["tags"], .array([.string("verb")]))
        XCTAssertEqual(item?["createdAt"]?.stringValue, "2026-10-01T10:00:00Z")
        XCTAssertNotNil(item?["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let keys = Set(item?.objectValue?.keys.map { $0 } ?? [])
        XCTAssertEqual(keys, ["id", "key", "spanish", "translation", "partOfSpeech", "category", "tags", "createdAt"])
        XCTAssertFalse(keys.contains("pronunciationAudio"))
        XCTAssertFalse(keys.contains("chatData"))
    }

    func testLibraryWordsUnorganizedCategoryIsNull() async {
        addWord("uno", at: "2026-10-01T10:00:00Z")
        let result1 = await call("library.words")
        XCTAssertEqual(array(result1).first?["category"], .null)
    }

    func testLibraryWordsFiltersCategoryAndTagCaseInsensitively() async {
        addWord("uno", at: "2026-10-01T10:00:00Z", category: "Daily life", tags: ["Verb"])
        addWord("dos", at: "2026-10-02T10:00:00Z", category: "Work", tags: ["noun"])
        let byCategory = array(await call("library.words", .object(["category": .string("daily LIFE")])))
        XCTAssertEqual(byCategory.compactMap { $0["spanish"]?.stringValue }, ["uno"])
        let byTag = array(await call("library.words", .object(["tag": .string("VERB")])))
        XCTAssertEqual(byTag.compactMap { $0["spanish"]?.stringValue }, ["uno"])
    }

    func testLibraryWordsEmptyLibrary() async {
        let result2 = await call("library.words")
        XCTAssertEqual(array(result2), [])
    }

    func testLibraryWordsLimitClamped() async {
        for i in 0..<3 { addWord("w\(i)", at: "2026-10-0\(i + 1)T10:00:00Z") }
        let result3 = await call("library.words", .object(["limit": .number(0)]))
        XCTAssertEqual(array(result3).count, 1)
        let result4 = await call("library.words", .object(["limit": .number(9999)]))
        XCTAssertEqual(array(result4).count, 3)
    }

    func testLibraryWordsBadLimitTypeIsBadArgs() async {
        let result = await call("library.words", .object(["limit": .string("ten")]))
        guard case .failure(.badArgs) = result else { return XCTFail("expected badArgs, got \(result)") }
        let nonObject = await call("library.words", .string("x"))
        guard case .failure(.badArgs) = nonObject else { return XCTFail("expected badArgs, got \(nonObject)") }
    }

    func testLibraryWordsNullArgsMeanDefaults() async {
        addWord("uno", at: "2026-10-01T10:00:00Z")
        let result5 = await call("library.words", .null)
        XCTAssertEqual(array(result5).count, 1)
    }

    func testLibraryWordsNeedsGrant() async {
        let result = await call("library.words", granted: [])
        XCTAssertEqual(result, .failure(.notGranted))
    }

    // MARK: library.word

    func testLibraryWordByIdAndByKey() async {
        let word = addWord("Hablar", at: "2026-10-01T10:00:00Z")
        let byID = await call("library.word", .object(["id": .string(word.id.uuidString)]))
        guard case .success(let item) = byID else { return XCTFail("by id failed: \(byID)") }
        XCTAssertEqual(item["spanish"]?.stringValue, "Hablar")
        XCTAssertEqual(item["content"]?["word"]?.stringValue, "Hablar")
        XCTAssertEqual(item["content"]?["examples"]?.arrayValue?.count, 3)
        let byKey = await call("library.word", .object(["key": .string("hablar")]))
        XCTAssertEqual(byKey, byID)
        let byRawInput = await call("library.word", .object(["key": .string("  HABLAR ")]))
        XCTAssertEqual(byRawInput, byID)
    }

    func testLibraryWordNeitherArgIsBadArgs() async {
        guard case .failure(.badArgs) = await call("library.word") else { return XCTFail("expected badArgs") }
        guard case .failure(.badArgs) = await call("library.word", .object(["id": .string("not-a-uuid")])) else { return XCTFail("expected badArgs") }
    }

    func testLibraryWordMissing() async {
        let result = await call("library.word", .object(["id": .string(UUID().uuidString)]))
        XCTAssertEqual(result, .failure(.failed("word not found")))
    }

    // MARK: stats

    private func counts(_ rows: [JSONValue]) -> [Int] { rows.compactMap { $0["count"]?.intValue } }

    func testWordsPerDayZeroFilledOldestFirst() async {
        addWord("a", at: "2026-10-05T08:00:00Z")
        addWord("b", at: "2026-10-07T01:00:00Z")
        addWord("c", at: "2026-10-07T11:00:00Z")
        let rows = array(await call("stats.wordsPerDay", .object(["days": .number(3)])))
        XCTAssertEqual(rows.compactMap { $0["day"]?.stringValue }, ["2026-10-05", "2026-10-06", "2026-10-07"])
        XCTAssertEqual(counts(rows), [1, 0, 2])
    }

    func testWordsPerDayDayBoundary() async {
        addWord("late", at: "2026-10-05T23:59:59Z")
        addWord("early", at: "2026-10-06T00:00:00Z")
        let rows = array(await call("stats.wordsPerDay", .object(["days": .number(3)])))
        XCTAssertEqual(counts(rows), [1, 1, 0])
    }

    func testWordsPerDayRespectsCalendarTimeZone() async {
        var algiers = utc
        algiers.timeZone = TimeZone(identifier: "Africa/Algiers")! // UTC+1
        let fixedNow = now
        registry = CapabilityProviders.registry(words: words, artifacts: artifacts, calendar: algiers, now: { fixedNow })
        addWord("night", at: "2026-10-05T23:30:00Z") // 00:30 on the 6th in Algiers
        let rows = array(await call("stats.wordsPerDay", .object(["days": .number(3)])))
        XCTAssertEqual(rows.compactMap { $0["day"]?.stringValue }, ["2026-10-05", "2026-10-06", "2026-10-07"])
        XCTAssertEqual(counts(rows), [0, 1, 0])
    }

    func testWordsPerDayClampedAndDefaulted() async {
        let result6 = await call("stats.wordsPerDay", .object(["days": .number(0)]))
        XCTAssertEqual(array(result6).count, 1)
        let result7 = await call("stats.wordsPerDay", .object(["days": .number(9999)]))
        XCTAssertEqual(array(result7).count, 365)
        let result8 = await call("stats.wordsPerDay")
        XCTAssertEqual(array(result8).count, 7)
    }

    func testWordsPerDayEmptyLibraryIsAllZero() async {
        let result9 = await call("stats.wordsPerDay", .object(["days": .number(4)]))
        XCTAssertEqual(counts(array(result9)), [0, 0, 0, 0])
    }

    func testWordsPerWeekBuckets() async {
        addWord("thisWeek", at: "2026-10-05T09:00:00Z")       // Monday of the current week
        addWord("sundayBefore", at: "2026-10-04T23:00:00Z")    // week of 09-28
        addWord("mondayBefore", at: "2026-09-28T00:00:00Z")    // week of 09-28
        addWord("tooOld", at: "2026-09-20T12:00:00Z")          // week of 09-14, outside 3 weeks
        let rows = array(await call("stats.wordsPerWeek", .object(["weeks": .number(3)])))
        XCTAssertEqual(rows.compactMap { $0["weekStart"]?.stringValue }, ["2026-09-21", "2026-09-28", "2026-10-05"])
        XCTAssertEqual(counts(rows), [0, 2, 1])
    }

    func testWordsPerWeekClamped() async {
        let result10 = await call("stats.wordsPerWeek", .object(["weeks": .number(0)]))
        XCTAssertEqual(array(result10).count, 1)
        let result11 = await call("stats.wordsPerWeek", .object(["weeks": .number(999)]))
        XCTAssertEqual(array(result11).count, 104)
        let result12 = await call("stats.wordsPerWeek")
        XCTAssertEqual(array(result12).count, 8)
    }

    // MARK: storage

    func testStorageRoundTripPersistent() async {
        let artifact = artifacts.create(title: "t", kind: .spec, payload: Data("{}".utf8), requested: [], prompt: "", now: now)
        guard case .success(let saved) = artifact else { return XCTFail("create failed") }
        let real = ArtifactSession(artifactID: saved.id, dryRun: false)
        let result13 = await call("storage.get", .object(["key": .string("k")]), session: real, granted: [])
        XCTAssertEqual(result13, .success(.null))
        let value = JSONValue.object(["n": .number(3), "list": .array([.string("a")])])
        let result14 = await call("storage.set", .object(["key": .string("k"), "value": value]), session: real, granted: [])
        XCTAssertEqual(result14, .success(.object([:])))
        let result15 = await call("storage.get", .object(["key": .string("k")]), session: real, granted: [])
        XCTAssertEqual(result15, .success(value))
        XCTAssertNotNil(artifacts.stateValue(artifactID: saved.id, key: "k"))
        let result16 = await call("storage.remove", .object(["key": .string("k")]), session: real, granted: [])
        XCTAssertEqual(result16, .success(.object([:])))
        let result17 = await call("storage.get", .object(["key": .string("k")]), session: real, granted: [])
        XCTAssertEqual(result17, .success(.null))
    }

    func testStorageDryRunDoesNotTouchRepository() async {
        let id = UUID()
        let preview = ArtifactSession(artifactID: id, dryRun: true)
        _ = await call("storage.set", .object(["key": .string("k"), "value": .string("v")]), session: preview, granted: [])
        XCTAssertNil(artifacts.stateValue(artifactID: id, key: "k"))
        let result18 = await call("storage.get", .object(["key": .string("k")]), session: preview, granted: [])
        XCTAssertEqual(result18, .success(.string("v")))
    }

    func testStorageUnsavedDraftUsesScratch() async {
        let draft = ArtifactSession(artifactID: nil, dryRun: true)
        _ = await call("storage.set", .object(["key": .string("k"), "value": .number(1)]), session: draft, granted: [])
        let result19 = await call("storage.get", .object(["key": .string("k")]), session: draft, granted: [])
        XCTAssertEqual(result19, .success(.number(1)))
        // A different artifact's scratch is separate.
        let other = ArtifactSession(artifactID: UUID(), dryRun: true)
        let result20 = await call("storage.get", .object(["key": .string("k")]), session: other, granted: [])
        XCTAssertEqual(result20, .success(.null))
    }

    func testStorageOverflowAndLongKeyMapToFailed() async {
        guard case .success(let saved) = artifacts.create(title: "t", kind: .spec, payload: Data("{}".utf8), requested: [], prompt: "", now: now) else { return XCTFail("create failed") }
        let real = ArtifactSession(artifactID: saved.id, dryRun: false)
        let longKey = await call("storage.set", .object(["key": .string(String(repeating: "k", count: 65)), "value": .number(1)]), session: real, granted: [])
        XCTAssertEqual(longKey, .failure(.failed("key too long")))
        // Six ~40 KB values fit under 256 KB; the seventh overflows.
        let big = JSONValue.string(String(repeating: "x", count: 40_000))
        var failure: Result<JSONValue, CapabilityError>?
        for i in 0..<9 {
            let result = await call("storage.set", .object(["key": .string("k\(i)"), "value": big]), session: real, granted: [])
            if case .failure = result { failure = result; break }
        }
        XCTAssertEqual(failure, .failure(.failed("storage full")))
    }

    func testStorageNeedsKeyAndValue() async {
        guard case .failure(.badArgs) = await call("storage.get", .object([:]), granted: []) else { return XCTFail("expected badArgs") }
        guard case .failure(.badArgs) = await call("storage.set", .object(["key": .string("k")]), granted: []) else { return XCTFail("expected badArgs") }
    }
}
