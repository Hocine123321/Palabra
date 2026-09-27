import Foundation
import SwiftData

/// One saved study flashcard, any subject (not limited to Spanish vocab).
/// Spaced-repetition fields mirror `SpacedRepetition.State`; `Flashcard`
/// converts to/from that pure struct so review logic stays independently
/// testable while this type stays a plain SwiftData row.
@Model
final class Flashcard {
    @Attribute(.unique) var id: UUID
    var subject: String
    var front: String
    var back: String
    var hint: String?
    var createdAt: Date

    var repetitions: Int
    var intervalDays: Double
    var easeFactor: Double
    var dueDate: Date

    init(subject: String, front: String, back: String, hint: String? = nil, createdAt: Date = Date()) {
        id = UUID()
        self.subject = subject
        self.front = front
        self.back = back
        self.hint = hint
        self.createdAt = createdAt
        let state = SpacedRepetition.State.new(now: createdAt)
        repetitions = state.repetitions
        intervalDays = state.intervalDays
        easeFactor = state.easeFactor
        dueDate = state.dueDate
    }

    var reviewState: SpacedRepetition.State {
        get { SpacedRepetition.State(repetitions: repetitions, intervalDays: intervalDays, easeFactor: easeFactor, dueDate: dueDate) }
        set {
            repetitions = newValue.repetitions
            intervalDays = newValue.intervalDays
            easeFactor = newValue.easeFactor
            dueDate = newValue.dueDate
        }
    }

    func isDue(on date: Date = Date()) -> Bool { dueDate <= date }
}
