import Foundation
import SwiftData

/// An exam as plain values, for a library backup. New fields must be optional.
struct ExamBackup: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var config: ExamConfig?
    var questionCount: Int
    var scoreSum: Double
    var durationSeconds: Double
    var records: [ExamAnswerRecord]
}

/// Hides SwiftData behind a small protocol, like the other repositories.
@MainActor
protocol ExamRepository {
    /// Newest first.
    func recent(limit: Int) -> [ExamResult]
    func result(id: UUID) -> ExamResult?
    @discardableResult
    func save(config: ExamConfig, records: [ExamAnswerRecord], duration: TimeInterval, now: Date) -> ExamResult?
    func delete(id: UUID)
    func deleteAll()
    /// How each word did across the last `exams` exams.
    func wordStats(lastExams exams: Int) -> [UUID: ExamWordStat]
    func backup() -> [ExamBackup]
    /// Adds the exams that are not here yet; `wordIDMap` re-points answers to the ids words have in this library.
    /// Returns how many were added. Throws `PersistenceError.saveFailed` (and adds nothing) when it cannot be written.
    func restore(_ exams: [ExamBackup], wordIDMap: [UUID: UUID]) throws -> Int
}

@MainActor
final class SwiftDataExamRepository: ExamRepository {
    /// Older exams beyond this are dropped.
    static let maxResults = 100

    private let context: ModelContext
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    /// A private in-memory store: the default for tests and previews that don't care about exams.
    static func inMemory() -> SwiftDataExamRepository {
        let container = try! ModelContainer(for: Schema([ExamResult.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataExamRepository(context: ModelContext(container), retaining: container)
    }

    func recent(limit: Int) -> [ExamResult] {
        var descriptor = FetchDescriptor<ExamResult>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = max(0, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    func result(id: UUID) -> ExamResult? {
        try? context.fetch(FetchDescriptor<ExamResult>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    func save(config: ExamConfig, records: [ExamAnswerRecord], duration: TimeInterval, now: Date) -> ExamResult? {
        guard !records.isEmpty else { return nil }
        let exam = ExamResult(config: config, records: records, duration: duration, now: now)
        context.insert(exam)
        trim()
        return Persistence.save(context) ? exam : nil
    }

    func delete(id: UUID) {
        guard let exam = result(id: id) else { return }
        context.delete(exam)
        Persistence.save(context)
    }

    func deleteAll() {
        for exam in (try? context.fetch(FetchDescriptor<ExamResult>())) ?? [] { context.delete(exam) }
        Persistence.save(context)
    }

    func wordStats(lastExams exams: Int) -> [UUID: ExamWordStat] {
        var stats: [UUID: ExamWordStat] = [:]
        for exam in recent(limit: exams) {
            for record in exam.records {
                for id in record.words {
                    var stat = stats[id] ?? ExamWordStat()
                    stat.attempts += 1
                    stat.scoreSum += record.score
                    stat.lastSeen = max(stat.lastSeen, exam.createdAt)
                    stats[id] = stat
                }
            }
        }
        return stats
    }

    func backup() -> [ExamBackup] {
        recent(limit: Self.maxResults).map {
            ExamBackup(id: $0.id, createdAt: $0.createdAt, config: $0.config, questionCount: $0.questionCount, scoreSum: $0.scoreSum, durationSeconds: $0.durationSeconds, records: $0.records)
        }
    }

    func restore(_ exams: [ExamBackup], wordIDMap: [UUID: UUID]) throws -> Int {
        var added = 0
        var seen = Set<UUID>()
        for backup in exams where seen.insert(backup.id).inserted && result(id: backup.id) == nil {
            let records = backup.records.map { record -> ExamAnswerRecord in
                var copy = record
                copy.wordID = wordIDMap[record.wordID] ?? record.wordID
                copy.involvedWordIDs = record.involvedWordIDs?.map { wordIDMap[$0] ?? $0 }
                return copy
            }
            let exam = ExamResult(config: backup.config ?? ExamConfig(), records: records, duration: backup.durationSeconds, now: backup.createdAt)
            exam.id = backup.id
            exam.scoreSum = backup.scoreSum.isFinite ? min(max(backup.scoreSum, 0), Double(records.count)) : exam.scoreSum
            context.insert(exam)
            added += 1
        }
        guard added > 0 else { return 0 }
        trim()
        guard Persistence.save(context) else {
            context.rollback()
            throw PersistenceError.saveFailed
        }
        return added
    }

    private func trim() {
        let all = recent(limit: Int.max)
        guard all.count > Self.maxResults else { return }
        for exam in all.dropFirst(Self.maxResults) { context.delete(exam) }
    }
}
