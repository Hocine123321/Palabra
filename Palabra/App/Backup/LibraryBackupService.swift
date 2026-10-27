import Foundation

/// Exports and imports the whole library as one `.palabra` file (see `ArchiveFormat`): the words with their
/// organization, tags, chats and pronunciation clips, the person's decks and cards with the study progress and
/// review history, and the assistant conversations. An export made by an earlier version (one JSON file of
/// words) still imports.
@MainActor
final class LibraryBackupService {
    struct ExportSummary: Equatable {
        var url: URL
        var words: Int
        var clips: Int
        var cards: Int
        var chats: Int
        var bytes: Int64
        var exams = 0
    }

    struct ImportSummary: Equatable {
        var words = WordRestoreResult()
        var decks = 0
        var cards = 0
        /// Cards that took over study progress from the file.
        var progress = 0
        var reviews = 0
        var chats = 0
        var exams = 0
        /// Clips the file lists but could not be read from it (damaged or not a sound file).
        var clipsLost = 0
        /// Imported from the old JSON format.
        var legacy = false
    }

    enum Failure: Error, Equatable {
        /// Not a Palabra export (or not readable at all).
        case notALibrary
        /// Made by a newer version of the app.
        case unsupportedVersion
        /// Cut short, for example an interrupted download.
        case incomplete
        /// Damaged: the content does not match its checksum.
        case corrupt
        /// The library could not be written (what was already added stays, and importing again skips it).
        case saveFailed
        /// The export file could not be written.
        case writeFailed
    }

    static let fileExtension = "palabra"
    static let namePrefix = "Palabra-Library-"
    /// A pronunciation clip is a few hundred KB; a bigger "clip" in a file is not one.
    static let maxClipBytes = 8_000_000
    static let wordChunk = 100
    static let logChunk = 2_000

    private let words: WordRepository
    private let cards: CardRepository
    private let chats: ChatRepository
    private let exams: ExamRepository?
    private let directory: URL
    private let appVersion: String?
    private let now: () -> Date
    /// Runs after the words are restored and before the study part, so the vocabulary cards exist when their progress arrives.
    private let afterWords: () -> Void

    init(
        words: WordRepository,
        cards: CardRepository,
        chats: ChatRepository,
        exams: ExamRepository? = nil,
        directory: URL = FileManager.default.temporaryDirectory,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        now: @escaping () -> Date = Date.init,
        afterWords: @escaping () -> Void = {}
    ) {
        self.words = words
        self.cards = cards
        self.chats = chats
        self.exams = exams
        self.directory = directory
        self.appVersion = appVersion
        self.now = now
        self.afterWords = afterWords
    }

    // MARK: - Export

    func export() async throws -> ExportSummary {
        removeOldExports()
        let date = now()
        let url = directory.appendingPathComponent("\(Self.namePrefix)\(date.formatted(.iso8601.year().month().day())).\(Self.fileExtension)")
        let writer: ArchiveWriter
        do { writer = try ArchiveWriter(url: url) } catch { throw Failure.writeFailed }
        do {
            var records = words.backupRecords()
            var clips = 0
            for index in records.indices {
                if let clip = words.pronunciation(id: records[index].id), !clip.isEmpty {
                    records[index].audio = try writer.addBlob(clip)
                    clips += 1
                }
                // Keep the screen responsive on a large library (compressing the clips is the slow part).
                if index % 16 == 15 { await Task.yield() }
            }
            let study = cards.backup()
            let conversations = chats.backupConversations()
            let examHistory = exams?.backup() ?? []
            let archive = LibraryArchive(
                createdAt: date, appVersion: appVersion, words: records,
                study: study.isEmpty ? nil : study, chats: conversations.isEmpty ? nil : conversations,
                exams: examHistory.isEmpty ? nil : examHistory
            )
            try writer.finish(meta: archive)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return ExportSummary(url: url, words: records.count, clips: clips, cards: study.cards.count + study.vocabulary.count, chats: conversations.count, bytes: bytes, exams: examHistory.count)
        } catch {
            writer.cancel()
            throw Failure.writeFailed
        }
    }

    /// Only one export file is kept in the temporary folder; a new export replaces the last one.
    private func removeOldExports() {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix(Self.namePrefix) {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: - Import

    func importLibrary(from url: URL) async throws -> ImportSummary {
        do {
            let reader = try ArchiveReader(url: url)
            let archive = try reader.meta(LibraryArchive.self)
            guard archive.format == LibraryArchive.formatName else { throw Failure.notALibrary }
            guard archive.version <= LibraryArchive.currentVersion else { throw Failure.unsupportedVersion }
            return try await restore(archive, reader: reader)
        } catch ArchiveError.notAnArchive {
            return try await importLegacy(from: url)
        } catch ArchiveError.unsupportedVersion(_) {
            throw Failure.unsupportedVersion
        } catch ArchiveError.incomplete {
            throw Failure.incomplete
        } catch ArchiveError.corrupt {
            throw Failure.corrupt
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.notALibrary
        }
    }

    private func importLegacy(from url: URL) async throws -> ImportSummary {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let envelope = try? VocabularyLibraryExporter.decode(data) else { throw Failure.notALibrary }
        var summary = ImportSummary()
        summary.legacy = true
        summary.words = try await restoreWords(VocabularyLibraryExporter.records(from: envelope), reader: nil, lost: &summary.clipsLost)
        afterWords()
        return summary
    }

    private func restore(_ archive: LibraryArchive, reader: ArchiveReader) async throws -> ImportSummary {
        var summary = ImportSummary()
        summary.words = try await restoreWords(archive.words, reader: reader, lost: &summary.clipsLost)
        afterWords()
        let idMap = summary.words.idMap

        if let study = archive.study, !study.isEmpty {
            do {
                let result = try cards.restore(study, wordIDMap: idMap)
                summary.decks = result.decks
                summary.cards = result.cards
                summary.progress = result.progress
                var start = 0
                while start < study.logs.count {
                    let end = min(start + Self.logChunk, study.logs.count)
                    summary.reviews += try cards.restoreLogs(Array(study.logs[start..<end]), cardIDMap: result.cardIDMap)
                    start = end
                    await Task.yield()
                }
            } catch PersistenceError.saveFailed {
                throw Failure.saveFailed
            }
        }
        if let conversations = archive.chats, !conversations.isEmpty {
            do { summary.chats = try chats.restore(conversations, wordIDMap: idMap) } catch { throw Failure.saveFailed }
        }
        if let history = archive.exams, !history.isEmpty, let exams {
            do { summary.exams = try exams.restore(history, wordIDMap: idMap) } catch { throw Failure.saveFailed }
        }
        return summary
    }

    /// In chunks, so the screen stays responsive and a failure only affects the chunk being written (importing the same
    /// file again skips what is already there).
    private func restoreWords(_ records: [WordBackup], reader: ArchiveReader?, lost: inout Int) async throws -> WordRestoreResult {
        var total = WordRestoreResult()
        var lostClips = 0
        var start = 0
        while start < records.count {
            let end = min(start + Self.wordChunk, records.count)
            do {
                let part = try words.restore(Array(records[start..<end])) { record in
                    guard let ref = record.audio, let reader else { return nil }
                    guard let clip = reader.blob(ref), Self.isUsableClip(clip) else {
                        lostClips += 1
                        return nil
                    }
                    return clip
                }
                total.add(part)
            } catch {
                throw Failure.saveFailed
            }
            start = end
            await Task.yield()
        }
        lost += lostClips
        return total
    }

    /// A WAV file of a sane size (a damaged or hostile file cannot put arbitrary bytes where audio is played from).
    static func isUsableClip(_ data: Data) -> Bool {
        data.count > 44 && data.count <= maxClipBytes && data.prefix(4) == Data("RIFF".utf8)
    }
}
