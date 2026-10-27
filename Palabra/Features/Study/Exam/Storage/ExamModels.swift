import Foundation
import SwiftData

/// A finished exam, kept so the person can look back and so weak words can be found. New SwiftData entity:
/// stored property names are append-only once shipped (see AGENTS.md).
@Model
final class ExamResult {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// JSON of `ExamConfig`.
    var configData: Data
    var questionCount: Int
    /// Sum of the question scores (each 0...1).
    var scoreSum: Double
    var durationSeconds: Double
    /// JSON of `[ExamAnswerRecord]`.
    var recordsData: Data

    init(config: ExamConfig, records: [ExamAnswerRecord], duration: TimeInterval, now: Date) {
        id = UUID()
        createdAt = now
        configData = (try? JSONEncoder().encode(config)) ?? Data()
        questionCount = records.count
        scoreSum = records.reduce(0) { $0 + $1.score }
        durationSeconds = max(0, duration)
        recordsData = (try? JSONEncoder().encode(records)) ?? Data("[]".utf8)
    }

    var config: ExamConfig? { try? JSONDecoder().decode(ExamConfig.self, from: configData) }
    var records: [ExamAnswerRecord] { (try? JSONDecoder().decode([ExamAnswerRecord].self, from: recordsData)) ?? [] }
    /// 0...1.
    var fraction: Double { questionCount == 0 ? 0 : scoreSum / Double(questionCount) }
}
