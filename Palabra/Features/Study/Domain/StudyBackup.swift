import Foundation

/// The study side of a library backup, as plain values: the person's own decks and cards, how far each vocabulary
/// card has got (the cards themselves are rebuilt from the words), and the review history.
/// New fields must be optional, so a backup made by an older version keeps reading.
struct StudyBackup: Codable, Equatable, Sendable {
    struct SRS: Codable, Equatable, Sendable {
        var phase: String
        var interval: Double
        var ease: Double
        var reps: Int
        var lapses: Int
        var due: Date

        init(_ state: SRSState) {
            phase = state.phase.rawValue
            interval = state.interval
            ease = state.ease
            reps = state.reps
            lapses = state.lapses
            due = state.due
        }

        /// A damaged value never reaches the scheduler: unknown phases are new, numbers are kept in range.
        var state: SRSState {
            SRSState(
                phase: SRSPhase(rawValue: phase) ?? .new,
                interval: interval.isFinite ? min(max(interval, 0), SRSScheduler.maxIntervalDays) : 0,
                ease: ease.isFinite ? min(max(ease, SRSScheduler.minEase), SRSScheduler.maxEase) : SRSScheduler.startingEase,
                reps: max(0, reps),
                lapses: max(0, lapses),
                due: due
            )
        }
    }

    struct DeckRecord: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    struct CardRecord: Codable, Equatable, Sendable {
        var id: UUID
        var deckID: UUID
        var front: String
        var back: String
        var createdAt: Date
        var srs: SRS
    }

    /// How far one vocabulary card had got. Only cards that were studied are listed.
    struct VocabularyProgress: Codable, Equatable, Sendable {
        var cardID: UUID
        var wordID: UUID
        var srs: SRS
    }

    struct LogRecord: Codable, Equatable, Sendable {
        var id: UUID
        var cardID: UUID
        var grade: Int
        var reviewedAt: Date
        var prevInterval: Double
        var newInterval: Double
    }

    var decks: [DeckRecord] = []
    var cards: [CardRecord] = []
    var vocabulary: [VocabularyProgress] = []
    var logs: [LogRecord] = []

    var isEmpty: Bool { decks.isEmpty && cards.isEmpty && vocabulary.isEmpty && logs.isEmpty }
}

/// What restoring the study part did (the card id map is what the review history is attached through).
struct StudyRestoreResult: Equatable, Sendable {
    var decks = 0
    var cards = 0
    /// Vocabulary cards (and cards already in a deck) that took over the progress from the backup.
    var progress = 0
    /// Archived card id -> the id the card has in this library.
    var cardIDMap: [UUID: UUID] = [:]
}
