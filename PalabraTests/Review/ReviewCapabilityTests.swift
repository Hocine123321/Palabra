import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class ReviewCapabilityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var words: SwiftDataWordRepository!
    private var review: SwiftDataReviewRepository!
    private var registry: CapabilityRegistry!
    private let artifactID = UUID()
    private var session: ArtifactSession { ArtifactSession(artifactID: artifactID, dryRun: false) }
    private let granted: Set<String> = ["review.flag", "review.list"]

    override func setUp() {
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        words = SwiftDataWordRepository(context: context)
        review = SwiftDataReviewRepository.inMemory()
        registry = CapabilityProviders.registry(words: words, artifacts: SwiftDataArtifactRepository.inMemory(), review: review)
    }

    @discardableResult
    private func addWord(_ spanish: String) -> Word {
        let word = Word(spanish: spanish, key: WordKey.identity(spanish), searchKey: WordKey.search(spanish), content: StubAIClient.sampleContent(for: spanish), rawJSON: Data())
        context.insert(word)
        try? context.save()
        return word
    }

    private func flag(_ words: [JSONValue], session: ArtifactSession? = nil, granted: Set<String>? = nil) async -> Result<JSONValue, CapabilityError> {
        await registry.call(name: "review.flag", args: .object(["words": .array(words)]), session: session ?? self.session, granted: granted ?? self.granted)
    }

    func testFlagByIdAndByKeyAndUnresolvedAreListed() async throws {
        let hola = addWord("hola")
        addWord("Adiós")
        let result = await flag([
            .object(["id": .string(hola.id.uuidString), "score": .number(0.9), "note": .string("confused")]),
            .object(["key": .string("ADIÓS")]),
            .object(["key": .string("nada")]),
            .object(["id": .string(UUID().uuidString)]),
        ])
        guard case .success(let value) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(value["flagged"]?.intValue, 2)
        XCTAssertEqual(value["unresolved"]?.arrayValue?.count, 2)
        XCTAssertEqual(review.openCount(), 2)
        let need = try XCTUnwrap(review.openNeed(wordID: hola.id))
        XCTAssertEqual(need.score, 0.9)
        XCTAssertEqual(need.note, "confused")
        XCTAssertEqual(need.headword, "hola")
        XCTAssertEqual(need.sourceArtifactID, artifactID)
    }

    func testSameWordTwiceInOneCallIsOneFlagWithTheHigherScore() async throws {
        let hola = addWord("hola")
        _ = await flag([
            .object(["key": .string("hola"), "score": .number(0.3)]),
            .object(["id": .string(hola.id.uuidString), "score": .number(0.8)]),
        ])
        let need = try XCTUnwrap(review.openNeed(wordID: hola.id))
        XCTAssertEqual(need.flagCount, 1)
        XCTAssertEqual(need.score, 0.8)
    }

    func testBadArguments() async {
        addWord("hola")
        for bad: [JSONValue] in [
            [],
            [.string("hola")],
            [.object(["score": .number(0.5)])],
            [.object(["id": .string("not-a-uuid")])],
            [.object(["key": .string("hola"), "score": .string("high")])],
        ] {
            let result = await flag(bad)
            guard case .failure(.badArgs) = result else { XCTFail("expected badArgs for \(bad), got \(result)"); continue }
        }
        let tooMany = (0..<51).map { JSONValue.object(["key": .string("w\($0)")]) }
        guard case .failure(.badArgs) = await flag(tooMany) else { return XCTFail("expected badArgs for 51 words") }
        XCTAssertEqual(review.openCount(), 0)
    }

    func testDryRunDoesNotWrite() async {
        addWord("hola")
        let result = await flag([.object(["key": .string("hola")])], session: ArtifactSession(artifactID: nil, dryRun: true))
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value["flagged"]?.intValue, 0)
        XCTAssertEqual(review.openCount(), 0)
    }

    func testUngrantedFlagIsNotGranted() async {
        addWord("hola")
        let result = await flag([.object(["key": .string("hola")])], granted: [])
        XCTAssertEqual(result, .failure(.notGranted))
        XCTAssertEqual(review.openCount(), 0)
    }

    func testListReturnsOpenNeedsWeakestFirst() async throws {
        let a = addWord("hola"), b = addWord("adios")
        _ = await flag([.object(["id": .string(a.id.uuidString), "score": .number(0.2)]), .object(["id": .string(b.id.uuidString), "score": .number(0.9), "note": .string("n")])])
        let result = await registry.call(name: "review.list", args: .object([:]), session: session, granted: granted)
        guard case .success(.array(let items)) = result else { return XCTFail("expected array, got \(result)") }
        XCTAssertEqual(items.map { $0["headword"]?.stringValue }, ["adios", "hola"])
        XCTAssertEqual(items.first?["note"]?.stringValue, "n")
        XCTAssertEqual(items.first?["wordID"]?.stringValue, b.id.uuidString)
        XCTAssertEqual(items.first?["flagCount"]?.intValue, 1)
        XCTAssertNotNil(items.first?["updatedAt"]?.stringValue)
    }

    func testManualTeachesBothCapabilities() {
        let manual = registry.manual()
        XCTAssertTrue(manual.contains("review.flag"))
        XCTAssertTrue(manual.contains("review.list"))
    }
}
