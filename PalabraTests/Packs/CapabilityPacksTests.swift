import XCTest
import SwiftData
@testable import Palabra

/// `words.*` and `study.*` through the real registry with in-memory stores.
@MainActor
final class CapabilityPacksTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var words: SwiftDataWordRepository!
    private var cards: SwiftDataCardRepository!
    private var queue: SwiftDataWordQueueRepository!
    private var hooks: CapabilityHooks!
    private var registry: CapabilityRegistry!
    private var queuedSignals = 0
    private let session = ArtifactSession(artifactID: nil, dryRun: false)
    private let all: Set<String> = ["words.add", "words.place", "study.decks", "study.addCards", "library.words"]

    override func setUp() {
        container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        words = SwiftDataWordRepository(context: context)
        queue = SwiftDataWordQueueRepository(context: context)
        cards = SwiftDataCardRepository.inMemory()
        hooks = CapabilityHooks()
        queuedSignals = 0
        let box = self
        hooks.wordsQueued = { box.queuedSignals += 1 }
        hooks.language = { .arabic }
        registry = CapabilityProviders.registry(words: words, artifacts: SwiftDataArtifactRepository.inMemory(), cards: cards, wordQueue: queue, hooks: hooks)
    }

    @discardableResult
    private func addWord(_ spanish: String, category: String? = nil) -> Word {
        let word = Word(spanish: spanish, key: WordKey.identity(spanish), searchKey: WordKey.search(spanish), content: StubAIClient.sampleContent(for: spanish), rawJSON: Data())
        word.category = category
        context.insert(word)
        try? context.save()
        return word
    }

    private func call(_ name: String, _ args: JSONValue, dryRun: Bool = false, granted: Set<String>? = nil) async -> Result<JSONValue, CapabilityError> {
        await registry.call(name: name, args: args, session: ArtifactSession(artifactID: nil, dryRun: dryRun), granted: granted ?? all)
    }

    private func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }

    // MARK: words.add

    func testAddQueuesNewWordsSkipsKnownAndSignals() async throws {
        addWord("hola")
        _ = queue.enqueue(inputWord: "Adiós", mode: .new, language: .english)
        let result = await call("words.add", .object(["words": .array([.string("hola"), .string("adiós"), .string("madrugada"), .string("Madrugada"), .string(" nube ")])]))
        guard case .success(let value) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(value["queued"]?.intValue, 2)
        XCTAssertEqual(strings(value["alreadyInLibrary"]), ["hola"])
        XCTAssertEqual(strings(value["alreadyQueued"]), ["adiós"])
        let pending = queue.allItems().filter { $0.existingWordID == nil }
        XCTAssertEqual(Set(pending.map(\.inputWord)), ["Adiós", "madrugada", "nube"])
        XCTAssertEqual(pending.first { $0.inputWord == "nube" }?.language, .arabic)
        XCTAssertEqual(queuedSignals, 1)
    }

    func testAddWithNothingNewDoesNotSignal() async {
        addWord("hola")
        _ = await call("words.add", .object(["words": .array([.string("hola")])]))
        XCTAssertEqual(queuedSignals, 0)
    }

    func testAddBadArguments() async {
        for bad: JSONValue in [
            .object([:]),
            .object(["words": .array([])]),
            .object(["words": .array([.number(1)])]),
            .object(["words": .array([.string("   ")])]),
            .object(["words": .array([.string(String(repeating: "a", count: 81))])]),
            .object(["words": .array((0..<21).map { .string("w\($0)") })]),
        ] {
            guard case .failure(.badArgs) = await call("words.add", bad) else { XCTFail("expected badArgs for \(bad)"); continue }
        }
        XCTAssertTrue(queue.allItems().isEmpty)
    }

    func testAddDryRunWritesNothingAndNeedsGrant() async {
        let args = JSONValue.object(["words": .array([.string("nube")])])
        _ = await call("words.add", args, dryRun: true)
        XCTAssertTrue(queue.allItems().isEmpty)
        let ungranted = await call("words.add", args, granted: [])
        XCTAssertEqual(ungranted, .failure(.notGranted))
    }

    // MARK: words.place

    func testPlaceSetsCategoryAndTagsAndKeepsWhatIsOmitted() async throws {
        let hola = addWord("hola", category: "Greetings")
        hola.tags = ["a", "b"]
        let nube = addWord("nube")
        let result = await call("words.place", .object(["words": .array([
            .object(["id": .string(nube.id.uuidString), "category": .string("greetings"), "tags": .array([.string("#Sky"), .string("sky"), .string("weather")])]),
            .object(["key": .string("hola"), "tags": .array([.string("x")])]),
            .object(["key": .string("nada"), "category": .string("Other")]),
        ])]))
        guard case .success(let value) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(value["updated"]?.intValue, 2)
        XCTAssertEqual(strings(value["unresolved"]), ["nada"])
        let updatedNube = try XCTUnwrap(words.find(key: "nube"))
        XCTAssertEqual(updatedNube.category, "Greetings") // merged onto the known spelling
        XCTAssertEqual(updatedNube.tags, ["sky", "weather"])
        let updatedHola = try XCTUnwrap(words.find(key: "hola"))
        XCTAssertEqual(updatedHola.category, "Greetings")
        XCTAssertEqual(updatedHola.tags, ["x"])
    }

    func testPlaceBadArguments() async {
        let nube = addWord("nube")
        for bad: JSONValue in [
            .object(["words": .array([])]),
            .object(["words": .array([.object(["category": .string("A")])])]),
            .object(["words": .array([.object(["id": .string(nube.id.uuidString)])])]),
            .object(["words": .array([.object(["id": .string("nope"), "category": .string("A")])])]),
            .object(["words": .array([.object(["id": .string(nube.id.uuidString), "tags": .string("a")])])]),
            .object(["words": .array((0..<51).map { .object(["key": .string("w\($0)"), "category": .string("A")]) })]),
        ] {
            guard case .failure(.badArgs) = await call("words.place", bad) else { XCTFail("expected badArgs for \(bad)"); continue }
        }
        XCTAssertNil(words.find(key: "nube")?.category)
    }

    // MARK: study.*

    func testDecksListsCountsAndKinds() async throws {
        cards.createDeck(name: "Food", drafts: [CardDraft(front: "pan", back: "bread"), CardDraft(front: "agua", back: "water")], now: Date())
        let result = await call("study.decks", .object([:]))
        guard case .success(.array(let items)) = result else { return XCTFail("expected array, got \(result)") }
        let food = try XCTUnwrap(items.first { $0["name"]?.stringValue == "Food" })
        XCTAssertEqual(food["total"]?.intValue, 2)
        XCTAssertEqual(food["new"]?.intValue, 2)
        XCTAssertEqual(food["due"]?.intValue, 0)
        XCTAssertEqual(food["kind"]?.stringValue, "user")
    }

    func testAddCardsCreatesThenExtendsADeckIgnoringCaseAndDuplicates() async throws {
        let first = await call("study.addCards", .object(["deck": .string("Travel"), "cards": .array([
            .object(["front": .string("hola"), "back": .string("hello")]),
            .object(["front": .string("adiós"), "back": .string("bye")]),
        ])]))
        guard case .success(let created) = first else { return XCTFail("expected success, got \(first)") }
        XCTAssertEqual(created["created"]?.boolValue, true)
        XCTAssertEqual(created["added"]?.intValue, 2)

        let second = await call("study.addCards", .object(["deck": .string("travel"), "cards": .array([
            .object(["front": .string("HOLA"), "back": .string("Hello")]),
            .object(["front": .string("gracias"), "back": .string("thanks")]),
        ])]))
        guard case .success(let extended) = second else { return XCTFail("expected success, got \(second)") }
        XCTAssertEqual(extended["created"]?.boolValue, false)
        XCTAssertEqual(extended["added"]?.intValue, 1)
        XCTAssertEqual(extended["deck"]?.stringValue, "Travel")
        XCTAssertEqual(cards.decks().filter { $0.name == "Travel" }.count, 1)
    }

    func testAddCardsRespectsCreateFalseAndTheVocabularyDeck() async {
        let missing = await call("study.addCards", .object(["deck": .string("Nope"), "create": .bool(false), "cards": .array([.object(["front": .string("a"), "back": .string("b")])])]))
        guard case .failure(.failed) = missing else { return XCTFail("expected failed, got \(missing)") }
        cards.syncVocabulary([VocabularyCardEntry(wordID: UUID(), front: "hola", back: "hello")])
        let vocabulary = await call("study.addCards", .object(["deck": .string("Vocabulary"), "cards": .array([.object(["front": .string("a"), "back": .string("b")])])]))
        guard case .failure(.failed) = vocabulary else { return XCTFail("expected failed, got \(vocabulary)") }
        XCTAssertEqual(cards.decks().count, 1)
    }

    func testAddCardsBadArguments() async {
        for bad: JSONValue in [
            .object(["cards": .array([.object(["front": .string("a"), "back": .string("b")])])]),
            .object(["deck": .string(""), "cards": .array([.object(["front": .string("a"), "back": .string("b")])])]),
            .object(["deck": .string("D"), "cards": .array([])]),
            .object(["deck": .string("D"), "cards": .array([.object(["front": .string("a")])])]),
            .object(["deck": .string("D"), "cards": .array((0..<31).map { .object(["front": .string("f\($0)"), "back": .string("b")]) })]),
        ] {
            guard case .failure(.badArgs) = await call("study.addCards", bad) else { XCTFail("expected badArgs for \(bad)"); continue }
        }
        XCTAssertTrue(cards.decks().isEmpty)
    }

    func testDescribeLinesAreReadableAndManualListsThePacks() {
        let add = registry.capability(named: "words.add")?.describe?(.object(["words": .array([.string("a"), .string("b")])]))
        XCTAssertEqual(add, "Add words: a, b")
        let study = registry.capability(named: "study.addCards")?.describe?(.object(["deck": .string("Food"), "cards": .array([.null])]))
        XCTAssertEqual(study, "Add 1 card to the deck \"Food\"")
        let manual = registry.manual()
        for name in ["words.add", "words.place", "study.decks", "study.addCards"] { XCTAssertTrue(manual.contains(name)) }
    }
}
