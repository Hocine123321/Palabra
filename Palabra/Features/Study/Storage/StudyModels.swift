import Foundation
import SwiftData

enum DeckKind: String {
    /// The system deck mirrored from the Vocabulary library.
    case vocabulary
    case user
}

enum CardKind: String {
    case basic
}

/// A named set of cards. New SwiftData entity; persisted raw values are append-only once shipped.
@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var createdAt: Date

    init(name: String, kind: DeckKind, createdAt: Date = Date()) {
        id = UUID()
        self.name = name
        kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    var kind: DeckKind {
        get { DeckKind(rawValue: kindRaw) ?? .user }
        set { kindRaw = newValue.rawValue }
    }
}

/// One flashcard plus its spaced-repetition state. Decks are referenced by `deckID`
/// and mirrored words by `sourceWordID` (plain UUIDs, no @Relationship).
@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var deckID: UUID
    var front: String
    var back: String
    var kindRaw: String
    var sourceWordID: UUID?
    var due: Date
    var interval: Double
    var ease: Double
    var reps: Int
    var lapses: Int
    var phaseRaw: String
    var createdAt: Date

    init(deckID: UUID, front: String, back: String, sourceWordID: UUID? = nil, createdAt: Date = Date()) {
        id = UUID()
        self.deckID = deckID
        self.front = front
        self.back = back
        kindRaw = CardKind.basic.rawValue
        self.sourceWordID = sourceWordID
        due = createdAt
        interval = 0
        ease = SRSScheduler.startingEase
        reps = 0
        lapses = 0
        phaseRaw = SRSPhase.new.rawValue
        self.createdAt = createdAt
    }

    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .basic }

    var phase: SRSPhase { SRSPhase(rawValue: phaseRaw) ?? .new }

    var srs: SRSState {
        get { SRSState(phase: phase, interval: interval, ease: ease, reps: reps, lapses: lapses, due: due) }
        set {
            phaseRaw = newValue.phase.rawValue
            interval = newValue.interval
            ease = newValue.ease
            reps = newValue.reps
            lapses = newValue.lapses
            due = newValue.due
        }
    }
}

/// One answered review. Read later by quiz / dashboard features.
@Model
final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var cardID: UUID
    var gradeRaw: Int
    var reviewedAt: Date
    var prevInterval: Double
    var newInterval: Double

    init(cardID: UUID, grade: SRSGrade, reviewedAt: Date, prevInterval: Double, newInterval: Double) {
        id = UUID()
        self.cardID = cardID
        gradeRaw = grade.rawValue
        self.reviewedAt = reviewedAt
        self.prevInterval = prevInterval
        self.newInterval = newInterval
    }

    var grade: SRSGrade { SRSGrade(rawValue: gradeRaw) ?? .again }
}
