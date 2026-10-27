import XCTest
import SwiftData
@testable import Palabra

/// Exam history travels inside the `.palabra` file, and answers follow their words to the new library.
@MainActor
final class ExamBackupTests: XCTestCase {
    private var folder: URL!
    private var containers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("exam-backup-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private struct Side {
        let words: SwiftDataWordRepository
        let exams: SwiftDataExamRepository
        let service: LibraryBackupService
    }

    private func side(_ name: String, withExams: Bool = true) throws -> Side {
        let container = try ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        containers.append(container)
        let words = SwiftDataWordRepository(context: ModelContext(container), audio: PronunciationFileStore(directory: folder.appendingPathComponent("clips-\(name)")))
        let exams = SwiftDataExamRepository.inMemory()
        let service = LibraryBackupService(
            words: words, cards: SwiftDataCardRepository.inMemory(), chats: SwiftDataChatRepository.inMemory(),
            exams: withExams ? exams : nil, directory: folder.appendingPathComponent(name), appVersion: "9.9",
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        return Side(words: words, exams: exams, service: service)
    }

    private func add(_ word: String, to side: Side) -> Word {
        let content = WordContent(
            word: word,
            examples: [.init(context: "a", spanish: "uno", english: "one"), .init(context: "b", spanish: "dos", english: "two"), .init(context: "c", spanish: "tres", english: "three")],
            meaning: .init(translations: ["to speak"], explanation: "e"),
            usage: .init(explanation: "u", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "verb", groups: []),
            similarWords: []
        )
        return side.words.insert(spanish: word, key: WordKey.identity(word), searchKey: WordKey.search(word), content: content, rawJSON: Data())
    }

    private func record(_ word: UUID, _ score: Double) -> ExamAnswerRecord {
        ExamAnswerRecord(id: UUID(), wordID: word, headword: "hablar", kindRaw: "typeSpanish", score: score, given: "a", expected: "b")
    }

    func testExamsAreExportedAndImportedOnce() async throws {
        let source = try side("source")
        let hablar = add("hablar", to: source)
        _ = source.exams.save(config: ExamConfig(), records: [record(hablar.id, 1), record(hablar.id, 0)], duration: 30, now: Date(timeIntervalSince1970: 1_800_000_000))

        let summary = try await source.service.export()
        XCTAssertEqual(summary.exams, 1)

        let target = try side("target")
        let first = try await target.service.importLibrary(from: summary.url)
        XCTAssertEqual(first.exams, 1)
        let restored = try XCTUnwrap(target.exams.recent(limit: 5).first)
        XCTAssertEqual(restored.questionCount, 2)
        XCTAssertEqual(restored.fraction, 0.5, accuracy: 0.0001)
        let newID = try XCTUnwrap(target.words.find(key: WordKey.identity("hablar"))?.id)
        XCTAssertEqual(restored.records.map(\.wordID), [newID, newID])

        let second = try await target.service.importLibrary(from: summary.url)
        XCTAssertEqual(second.exams, 0)
        XCTAssertEqual(target.exams.recent(limit: 5).count, 1)
    }

    func testAnExportWithoutExamsHasNoneToImport() async throws {
        let source = try side("source")
        _ = add("hablar", to: source)
        let summary = try await source.service.export()
        XCTAssertEqual(summary.exams, 0)
        let target = try side("target")
        let imported = try await target.service.importLibrary(from: summary.url)
        XCTAssertEqual(imported.exams, 0)
        XCTAssertEqual(imported.words.imported, 1)
    }

    func testALibraryWithoutAnExamRepositorySkipsTheExamPart() async throws {
        let source = try side("source")
        let hablar = add("hablar", to: source)
        _ = source.exams.save(config: ExamConfig(), records: [record(hablar.id, 1)], duration: 5, now: Date())
        let summary = try await source.service.export()
        let target = try side("target", withExams: false)
        let imported = try await target.service.importLibrary(from: summary.url)
        XCTAssertEqual(imported.exams, 0)
        XCTAssertEqual(imported.words.imported, 1)
    }

    func testAnArchiveMadeBeforeExamsExistedStillDecodes() throws {
        // The file's header is a property list; an older one has no "exams" key.
        let header: [String: Any] = ["format": "Palabra Library", "version": 1, "createdAt": Date(timeIntervalSince1970: 0), "words": [Any]()]
        let data = try PropertyListSerialization.data(fromPropertyList: header, format: .binary, options: 0)
        let archive = try PropertyListDecoder().decode(LibraryArchive.self, from: data)
        XCTAssertNil(archive.exams)
        XCTAssertTrue(archive.words.isEmpty)
    }

    func testExamHistoryEncodesInTheFileHeaderFormat() throws {
        var config = ExamConfig()
        config.source = .words([UUID()])
        let entry = ExamBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 5), config: config, questionCount: 1, scoreSum: 1, durationSeconds: 3, records: [record(UUID(), 1)])
        let data = try PropertyListEncoder().encode([entry])
        XCTAssertEqual(try PropertyListDecoder().decode([ExamBackup].self, from: data), [entry])
    }
}
