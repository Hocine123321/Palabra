import Foundation

/// Decks, user cards, study stats and open review needs as mirror records. Like `mirrorWordRecords()`, this is where
/// the Study and Review types are turned into plain JSON; `Features/Mirroring` never sees them.
extension AppEnvironment {
    /// Collections `deck`, `card` (user decks only: the vocabulary deck is derived from the words), `stats` and `review`.
    /// Deck counts and stats are "as of" `now`, because the phone decides what is due; the page only shows them.
    func mirrorStudyCollections(now: Date = Date()) -> [MirrorCollection] {
        let formatter = ISO8601DateFormatter()
        func iso(_ date: Date) -> JSONValue { .string(formatter.string(from: date)) }

        let decks = cards.decks()
        let counts = cards.counts(now: now)
        let deckRecords = decks.map { deck -> MirrorRecord in
            let c = counts[deck.id] ?? DeckCounts()
            let payload: JSONValue = .object([
                "id": .string(deck.id.uuidString),
                "name": .string(deck.name),
                "kind": .string(deck.kind.rawValue),
                "createdAt": iso(deck.createdAt),
                "counts": .object(["total": .number(Double(c.total)), "due": .number(Double(c.due)), "new": .number(Double(c.new))]),
                "countsAt": iso(now),
            ])
            return MirrorRecord(kind: "deck", recordID: deck.id.uuidString, payload: payload)
        }
        let cardRecords = decks.filter { $0.kind == .user }.flatMap { deck in
            cards.cards(inDeck: deck.id).map { card -> MirrorRecord in
                let payload: JSONValue = .object([
                    "id": .string(card.id.uuidString),
                    "deckId": .string(deck.id.uuidString),
                    "front": .string(card.front),
                    "back": .string(card.back),
                    "due": iso(card.due),
                    "reps": .number(Double(card.reps)),
                    "lapses": .number(Double(card.lapses)),
                    "phase": .string(card.phaseRaw),
                    "createdAt": iso(card.createdAt),
                ])
                return MirrorRecord(kind: "card", recordID: card.id.uuidString, payload: payload)
            }
        }
        let stats = cards.reviewStats(now: now)
        let statsPayload: JSONValue = .object([
            "reviewedToday": .number(Double(stats.reviewedToday)),
            "streak": .number(Double(stats.streak)),
            "lastSevenDays": .array(stats.lastSevenDays.map { JSONValue.number(Double($0)) }),
            "asOf": iso(now),
        ])
        let reviewRecords = review.openNeeds().map { need -> MirrorRecord in
            let payload: JSONValue = .object([
                "id": .string(need.id.uuidString),
                "wordId": .string(need.wordID.uuidString),
                "headword": .string(need.headword),
                "translation": .string(need.translation),
                "score": .number(need.score),
                "note": .string(need.note),
                "flagCount": .number(Double(need.flagCount)),
                "updatedAt": iso(need.updatedAt),
            ])
            return MirrorRecord(kind: "review", recordID: need.id.uuidString, payload: payload)
        }
        return [
            MirrorCollection(kind: "deck", records: deckRecords),
            MirrorCollection(kind: "card", records: cardRecords),
            MirrorCollection(kind: "stats", records: [MirrorRecord(kind: "stats", recordID: "stats", payload: statsPayload)]),
            MirrorCollection(kind: "review", records: reviewRecords),
        ]
    }
}
