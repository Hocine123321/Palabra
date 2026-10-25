import XCTest
import SwiftData
@testable import Palabra

/// One self-contained library: the word, card and chat repositories (and the folder its clips live in).
@MainActor
private final class Library {
    let words: SwiftDataWordRepository
    let cards: SwiftDataCardRepository
    let chats: SwiftDataChatRepository
    let clipDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID().uuidString)")
    private let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        words = SwiftDataWordRepository(context: ModelContext(container), audio: PronunciationFileStore(directory: clipDirectory))
        cards = SwiftDataCardRepository.inMemory()
        chats = SwiftDataChatRepository.inMemory()
    }

    func syncCards() {
        cards.syncVocabulary(words.wordSummaries().map { VocabularyCardEntry(wordID: $0.id, front: $0.spanish, back: $0.translation) })
    }

    func service(directory: URL, afterWords: Bool = true) -> LibraryBackupService {
        LibraryBackupService(
            words: words, cards: cards, chats: chats, directory: directory, appVersion: "9.9",
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            afterWords: { [self] in if afterWords { syncCards() } }
        )
    }

    func add(_ word: String, translation: String = "to speak") -> Word {
        let content = WordContent(
            word: word,
            examples: [
                .init(context: "a", spanish: "uno", english: "one"),
                .init(context: "b", spanish: "dos", english: "two"),
                .init(context: "c", spanish: "tres", english: "three"),
            ],
            meaning: .init(translations: [translation], explanation: "explanation"),
            usage: .init(explanation: "usage", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: []),
            similarWords: []
        )
        return words.insert(spanish: word, key: WordKey.identity(word), searchKey: WordKey.search(word), content: content, rawJSON: Data())
    }

    func cleanUp() { try? FileManager.default.removeItem(at: clipDirectory) }
}

@MainActor
final class LibraryBackupServiceTests: XCTestCase {
    private var folder: URL!
    private var libraries: [Library] = []

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        libraries.forEach { $0.cleanUp() }
        super.tearDown()
    }

    private func library() -> Library {
        let library = Library()
        libraries.append(library)
        return library
    }

    private func wav(_ marker: UInt8) -> Data {
        var data = Data("RIFF".utf8)
        data.append(Data(repeating: marker, count: 400))
        return data
    }

    /// A library with a section, tags, a clip, a chat, study progress and a deck.
    private func fullLibrary() throws -> (Library, hablar: Word) {
        let source = library()
        let hablar = source.add("hablar")
        let comer = source.add("comer", translation: "to eat")
        source.words.updatePlacement(id: hablar.id, category: "Verbs", tags: ["common"])
        source.words.updatePronunciation(id: hablar.id, audio: wav(1))
        source.words.updateChat(id: hablar.id, messages: [ChatMessage(role: .user, text: "hola")])
        source.syncCards()
        let vocabulary = try XCTUnwrap(source.cards.decks().first { $0.kind == .vocabulary })
        let card = try XCTUnwrap(source.cards.cards(inDeck: vocabulary.id).first { $0.sourceWordID == hablar.id })
        _ = source.cards.record(cardID: card.id, grade: .good, now: Date(timeIntervalSince1970: 1_800_000_000))
        let deck = source.cards.createDeck(name: "Trip", drafts: [CardDraft(front: "gato", back: "cat"), CardDraft(front: "perro", back: "dog")], now: Date(timeIntervalSince1970: 1_700_000_000))
        let tripCard = try XCTUnwrap(source.cards.cards(inDeck: deck.id).first)
        _ = source.cards.record(cardID: tripCard.id, grade: .easy, now: Date(timeIntervalSince1970: 1_800_000_100))
        _ = source.chats.create(title: "About hablar", wordID: hablar.id, turns: [ChatTurn(role: .user, text: "¿hablar?")], now: Date(timeIntervalSince1970: 1_800_000_000))
        _ = comer
        return (source, hablar)
    }

    func testExportWritesOneCompactFileWithTheCounts() async throws {
        let (source, _) = try fullLibrary()
        let summary = try await source.service(directory: folder).export()
        XCTAssertEqual(summary.url.pathExtension, "palabra")
        XCTAssertTrue(summary.url.lastPathComponent.hasPrefix(LibraryBackupService.namePrefix))
        XCTAssertEqual(summary.words, 2)
        XCTAssertEqual(summary.clips, 1)
        XCTAssertEqual(summary.chats, 1)
        XCTAssertGreaterThan(summary.bytes, 0)
        let head = try Data(contentsOf: summary.url).prefix(4)
        XCTAssertEqual(head, Data("PLBR".utf8), "binary container, not JSON")
    }

    func testANewExportReplacesThePreviousFile() async throws {
        let (source, _) = try fullLibrary()
        let service = source.service(directory: folder)
        _ = try await service.export()
        _ = try await service.export()
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Palabra-Library-") }
        XCTAssertEqual(files.count, 1)
    }

    func testExportThenImportRestoresTheWholeLibraryIntoAFreshOne() async throws {
        let (source, hablar) = try fullLibrary()
        let file = try await source.service(directory: folder).export().url

        let target = library()
        let summary = try await target.service(directory: folder).importLibrary(from: file)
        XCTAssertEqual(summary.words.imported, 2)
        XCTAssertEqual(summary.words.clipsRestored, 1)
        XCTAssertEqual(summary.chats, 1)
        XCTAssertEqual(summary.decks, 1)
        XCTAssertEqual(summary.cards, 2)
        XCTAssertEqual(summary.progress, 1, "the studied vocabulary card (deck cards are created with their progress)")
        XCTAssertEqual(summary.reviews, 2)
        XCTAssertEqual(summary.clipsLost, 0)
        XCTAssertFalse(summary.legacy)

        let restored = try XCTUnwrap(target.words.find(key: "hablar"))
        XCTAssertEqual(restored.id, hablar.id)
        XCTAssertEqual(restored.category, "Verbs")
        XCTAssertEqual(restored.tags, ["common"])
        XCTAssertEqual(restored.chat.first?.text, "hola")
        XCTAssertEqual(target.words.pronunciation(id: restored.id), wav(1))

        let vocabulary = try XCTUnwrap(target.cards.decks().first { $0.kind == .vocabulary })
        let card = try XCTUnwrap(target.cards.cards(inDeck: vocabulary.id).first { $0.sourceWordID == restored.id })
        XCTAssertNotEqual(card.phase, .new)
        let trip = try XCTUnwrap(target.cards.decks().first { $0.name == "Trip" })
        XCTAssertEqual(target.cards.cards(inDeck: trip.id).count, 2)
        XCTAssertEqual(target.chats.conversation(forWordID: restored.id)?.title, "About hablar")
    }

    func testImportingTheSameFileTwiceAddsNothingTheSecondTime() async throws {
        let (source, _) = try fullLibrary()
        let file = try await source.service(directory: folder).export().url
        let target = library()
        let service = target.service(directory: folder)
        _ = try await service.importLibrary(from: file)
        let second = try await service.importLibrary(from: file)
        XCTAssertEqual(second.words.imported, 0)
        XCTAssertEqual(second.words.skipped, 2)
        XCTAssertEqual(second.decks, 0)
        XCTAssertEqual(second.cards, 0)
        XCTAssertEqual(second.reviews, 0)
        XCTAssertEqual(second.chats, 0)
        XCTAssertEqual(target.words.wordCount(), 2)
    }

    func testImportKeepsProgressTheLibraryAlreadyHas() async throws {
        let (source, _) = try fullLibrary()
        let file = try await source.service(directory: folder).export().url
        let target = library()
        _ = target.add("hablar")
        target.syncCards()
        let vocabulary = try XCTUnwrap(target.cards.decks().first { $0.kind == .vocabulary })
        let card = try XCTUnwrap(target.cards.cards(inDeck: vocabulary.id).first)
        let own = try XCTUnwrap(target.cards.record(cardID: card.id, grade: .easy, now: Date(timeIntervalSince1970: 1_810_000_000)))
        _ = try await target.service(directory: folder).importLibrary(from: file)
        let after = try XCTUnwrap(target.cards.cards(inDeck: vocabulary.id).first { $0.id == card.id })
        XCTAssertEqual(after.srs, own)
    }

    func testAnOldJSONExportStillImports() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = library()
        let word = source.add("hablar")
        let item = VocabularyLibraryExporter.Item(content: word.content, raw: Data(), createdAt: now, updatedAt: now, chat: [])
        let file = folder.appendingPathComponent("old.json")
        try VocabularyLibraryExporter.encode(items: [item]).write(to: file)
        let target = library()
        let summary = try await target.service(directory: folder).importLibrary(from: file)
        XCTAssertTrue(summary.legacy)
        XCTAssertEqual(summary.words.imported, 1)
        XCTAssertNotNil(target.words.find(key: "hablar"))
    }

    func testFilesThatAreNotLibrariesAreRefused() async throws {
        let target = library()
        let service = target.service(directory: folder)
        let junk = folder.appendingPathComponent("junk.palabra")
        try Data("hello".utf8).write(to: junk)
        await assertImportFails(service, junk, .notALibrary)
        let missing = folder.appendingPathComponent("missing.palabra")
        await assertImportFails(service, missing, .notALibrary)
    }

    func testTruncatedAndDamagedFilesGetTheirOwnErrors() async throws {
        let (source, _) = try fullLibrary()
        let file = try await source.service(directory: folder).export().url
        let full = try Data(contentsOf: file)
        let target = library()
        let service = target.service(directory: folder)

        let cut = folder.appendingPathComponent("cut.palabra")
        try full.prefix(full.count / 2).write(to: cut)
        await assertImportFails(service, cut, .incomplete)

        var damaged = full
        damaged[damaged.count - ArchiveFormat.footerSize - 5] ^= 0xFF
        let bad = folder.appendingPathComponent("bad.palabra")
        try damaged.write(to: bad)
        await assertImportFails(service, bad, .corrupt)
        XCTAssertEqual(target.words.wordCount(), 0, "nothing is imported from a damaged file")
    }

    func testADamagedClipOnlyLosesThatClip() async throws {
        let (source, hablar) = try fullLibrary()
        let file = try await source.service(directory: folder).export().url
        let reader = try ArchiveReader(url: file)
        let archive = try reader.meta(LibraryArchive.self)
        let ref = try XCTUnwrap(archive.words.first { $0.id == hablar.id }?.audio)
        var data = try Data(contentsOf: file)
        data[Int(ref.offset) + 1] ^= 0xFF
        let damaged = folder.appendingPathComponent("clip.palabra")
        try data.write(to: damaged)

        let target = library()
        let summary = try await target.service(directory: folder).importLibrary(from: damaged)
        XCTAssertEqual(summary.words.imported, 2)
        XCTAssertEqual(summary.clipsLost, 1)
        XCTAssertFalse(target.words.hasPronunciation(id: hablar.id))
    }

    func testClipThatIsNotAWAVIsNotUsed() {
        XCTAssertTrue(LibraryBackupService.isUsableClip(wav(1)))
        XCTAssertFalse(LibraryBackupService.isUsableClip(Data("RIFF".utf8)))
        XCTAssertFalse(LibraryBackupService.isUsableClip(Data(repeating: 0, count: 500)))
        XCTAssertFalse(LibraryBackupService.isUsableClip(Data("RIFF".utf8) + Data(repeating: 0, count: LibraryBackupService.maxClipBytes)))
    }

    func testExportToAnUnwritableFolderFails() async throws {
        let source = library()
        _ = source.add("hablar")
        let missing = folder.appendingPathComponent("nope/nope")
        do {
            _ = try await source.service(directory: missing).export()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? LibraryBackupService.Failure, .writeFailed)
        }
    }

    private func assertImportFails(_ service: LibraryBackupService, _ url: URL, _ expected: LibraryBackupService.Failure, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await service.importLibrary(from: url)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LibraryBackupService.Failure, expected, file: file, line: line)
        }
    }
}
