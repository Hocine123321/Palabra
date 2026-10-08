import Foundation
import SwiftData

/// Hides SwiftData behind a small protocol, like `WordRepository`.
@MainActor
protocol CardRepository {
    /// Vocabulary deck first, then by creation date.
    func decks() -> [Deck]
    func cards(inDeck id: UUID) -> [Card]
    func counts(now: Date) -> [UUID: DeckCounts]
    /// Due cards (oldest first) followed by new cards, capped by what is left of today's `newLimit`.
    /// `deckID == nil` means every deck.
    func studyQueue(deckID: UUID?, now: Date, newLimit: Int) -> [Card]
    @discardableResult
    func createDeck(name: String, drafts: [CardDraft], now: Date) -> Deck
    func deleteDeck(id: UUID)
    /// Adds cards to a user deck, skipping blanks and cards already in it (same front and back, ignoring case).
    /// Returns how many were added; 0 for an unknown deck or the system Vocabulary deck.
    @discardableResult
    func addCards(toDeck id: UUID, drafts: [CardDraft], now: Date) -> Int
    /// Applies the scheduler to one card and writes the card plus a `ReviewLog` together.
    @discardableResult
    func record(cardID: UUID, grade: SRSGrade, now: Date) -> SRSState?
    /// Makes the system Vocabulary deck match `entries` exactly. Idempotent: keyed on
    /// `sourceWordID`, keeps scheduling state of existing cards, removes cards (and their
    /// logs) for words that are gone.
    func syncVocabulary(_ entries: [VocabularyCardEntry])
}

@MainActor
final class SwiftDataCardRepository: CardRepository {
    static let vocabularyDeckName = "Vocabulary"

    private let context: ModelContext
    private let scheduler = SRSScheduler()
    /// Keeps an in-memory container alive when this repository owns it.
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    /// A private in-memory store: the default for tests and previews that don't care about cards.
    static func inMemory() -> SwiftDataCardRepository {
        let schema = Schema([Deck.self, Card.self, ReviewLog.self])
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataCardRepository(context: ModelContext(container), retaining: container)
    }

    func decks() -> [Deck] {
        let all = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        return all.sorted { a, b in
            let ra = a.kind == .vocabulary ? 0 : 1
            let rb = b.kind == .vocabulary ? 0 : 1
            return ra != rb ? ra < rb : a.createdAt < b.createdAt
        }
    }

    func cards(inDeck id: UUID) -> [Card] {
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == id }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func counts(now: Date) -> [UUID: DeckCounts] {
        var result: [UUID: DeckCounts] = [:]
        for card in allCards() {
            var c = result[card.deckID] ?? DeckCounts()
            c.total += 1
            if card.phase == .new {
                c.new += 1
            } else if card.due <= now {
                c.due += 1
            }
            result[card.deckID] = c
        }
        return result
    }

    func studyQueue(deckID: UUID?, now: Date, newLimit: Int) -> [Card] {
        let pool = allCards().filter { deckID == nil || $0.deckID == deckID }
        let due = pool.filter { $0.phase != .new && $0.due <= now }.sorted { $0.due < $1.due }
        let startOfDay = Calendar.current.startOfDay(for: now)
        let remaining = max(0, newLimit - newCardsStudied(since: startOfDay))
        let fresh = pool.filter { $0.phase == .new }.sorted { $0.createdAt < $1.createdAt }.prefix(remaining)
        return due + Array(fresh)
    }

    @discardableResult
    func createDeck(name: String, drafts: [CardDraft], now: Date) -> Deck {
        let deck = Deck(name: name, kind: .user, createdAt: now)
        context.insert(deck)
        for draft in drafts {
            let front = draft.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            context.insert(Card(deckID: deck.id, front: front, back: back, createdAt: now))
        }
        try? context.save()
        return deck
    }

    @discardableResult
    func addCards(toDeck id: UUID, drafts: [CardDraft], now: Date) -> Int {
        guard let deck = decks().first(where: { $0.id == id }), deck.kind == .user else { return 0 }
        func normalized(_ front: String, _ back: String) -> String { "\(front.lowercased())\u{1F}\(back.lowercased())" }
        var seen = Set(cards(inDeck: id).map { normalized($0.front, $0.back) })
        var added = 0
        for draft in drafts {
            let front = draft.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty, seen.insert(normalized(front, back)).inserted else { continue }
            context.insert(Card(deckID: id, front: front, back: back, createdAt: now))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    func deleteDeck(id: UUID) {
        let descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
        guard let deck = try? context.fetch(descriptor).first else { return }
        delete(cards: cards(inDeck: id))
        context.delete(deck)
        try? context.save()
    }

    @discardableResult
    func record(cardID: UUID, grade: SRSGrade, now: Date) -> SRSState? {
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == cardID })
        guard let card = try? context.fetch(descriptor).first else { return nil }
        let previous = card.srs
        let updated = scheduler.next(previous, grade: grade, now: now)
        card.srs = updated
        context.insert(ReviewLog(cardID: cardID, grade: grade, reviewedAt: now, prevInterval: previous.interval, newInterval: updated.interval))
        try? context.save()
        return updated
    }

    func syncVocabulary(_ entries: [VocabularyCardEntry]) {
        var deck = decks().first { $0.kind == .vocabulary }
        if deck == nil {
            guard !entries.isEmpty else { return }
            let created = Deck(name: Self.vocabularyDeckName, kind: .vocabulary)
            context.insert(created)
            deck = created
        }
        guard let deck else { return }
        let deckID = deck.id

        var bySource: [UUID: Card] = [:]
        var stale: [Card] = []
        for card in cards(inDeck: deckID) {
            if let source = card.sourceWordID, bySource[source] == nil {
                bySource[source] = card
            } else {
                stale.append(card) // no source, or a duplicate for the same word
            }
        }
        let wanted = Set(entries.map(\.wordID))
        for (source, card) in bySource where !wanted.contains(source) { stale.append(card) }

        for entry in entries {
            if let card = bySource[entry.wordID] {
                if card.front != entry.front { card.front = entry.front }
                if card.back != entry.back { card.back = entry.back }
            } else {
                context.insert(Card(deckID: deckID, front: entry.front, back: entry.back, sourceWordID: entry.wordID))
            }
        }
        delete(cards: stale)
        try? context.save()
    }

    // MARK: - Helpers

    private func allCards() -> [Card] {
        (try? context.fetch(FetchDescriptor<Card>())) ?? []
    }

    /// Cards whose first-ever review happened on or after `start`.
    private func newCardsStudied(since start: Date) -> Int {
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
        let before = Set(logs.filter { $0.reviewedAt < start }.map(\.cardID))
        let today = Set(logs.filter { $0.reviewedAt >= start }.map(\.cardID))
        return today.subtracting(before).count
    }

    private func delete(cards: [Card]) {
        guard !cards.isEmpty else { return }
        let ids = Set(cards.map(\.id))
        for log in (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? [] where ids.contains(log.cardID) {
            context.delete(log)
        }
        for card in cards { context.delete(card) }
    }
}
