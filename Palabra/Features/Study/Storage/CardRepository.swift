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
    /// Removes one card (and its review history) from a user deck. The system Vocabulary deck is managed by the library, so it is left alone.
    @discardableResult
    func deleteCard(id: UUID) -> Bool
    /// Today's answers, the streak and the last seven days, from the review history.
    func reviewStats(now: Date) -> StudyStats
    /// Applies the scheduler to one card and writes the card plus a `ReviewLog` together.
    @discardableResult
    func record(cardID: UUID, grade: SRSGrade, now: Date) -> SRSState?
    /// Makes the system Vocabulary deck match `entries` exactly. Idempotent: keyed on
    /// `sourceWordID`, keeps scheduling state of existing cards, removes cards (and their
    /// logs) for words that are gone.
    func syncVocabulary(_ entries: [VocabularyCardEntry])
    /// The person's decks and cards, the progress on vocabulary cards and the review history, for a backup.
    func backup() -> StudyBackup
    /// Merges decks, cards and progress from a backup (without the history, see `restoreLogs`). Never replaces
    /// progress the person already has: a card takes the backup's progress only while it is still new.
    /// Throws `PersistenceError.saveFailed` (and changes nothing) when it cannot be written.
    func restore(_ backup: StudyBackup, wordIDMap: [UUID: UUID]) throws -> StudyRestoreResult
    /// Adds review history entries whose card is in `cardIDMap`, skipping ones already here. Returns how many were added.
    func restoreLogs(_ logs: [StudyBackup.LogRecord], cardIDMap: [UUID: UUID]) throws -> Int
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

    /// Counted in the store (three small count queries per deck) instead of loading every card: this runs on
    /// launch, on every tab change and on every Study screen, so it must stay cheap for a large library.
    func counts(now: Date) -> [UUID: DeckCounts] {
        let newRaw = SRSPhase.new.rawValue
        var result: [UUID: DeckCounts] = [:]
        for deck in decks() {
            let id = deck.id
            let total = count(FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == id }))
            guard total > 0 else { continue }
            let new = count(FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == id && $0.phaseRaw == newRaw }))
            let due = count(FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == id && $0.phaseRaw != newRaw && $0.due <= now }))
            result[id] = DeckCounts(total: total, due: due, new: new)
        }
        return result
    }

    func studyQueue(deckID: UUID?, now: Date, newLimit: Int) -> [Card] {
        let newRaw = SRSPhase.new.rawValue
        let dueDescriptor: FetchDescriptor<Card>
        if let deckID {
            dueDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == deckID && $0.phaseRaw != newRaw && $0.due <= now }, sortBy: [SortDescriptor(\.due)])
        } else {
            dueDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.phaseRaw != newRaw && $0.due <= now }, sortBy: [SortDescriptor(\.due)])
        }
        let due = (try? context.fetch(dueDescriptor)) ?? []

        let startOfDay = SRSScheduler.studyDayStart(for: now)
        let remaining = max(0, newLimit - newCardsStudied(since: startOfDay))
        // A fetch limit of 0 means "no limit" to the store, so never ask for it.
        guard remaining > 0 else { return due }
        var freshDescriptor: FetchDescriptor<Card>
        if let deckID {
            freshDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.deckID == deckID && $0.phaseRaw == newRaw }, sortBy: [SortDescriptor(\.createdAt)])
        } else {
            freshDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.phaseRaw == newRaw }, sortBy: [SortDescriptor(\.createdAt)])
        }
        freshDescriptor.fetchLimit = remaining
        let fresh = (try? context.fetch(freshDescriptor)) ?? []
        return due + fresh
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
        Persistence.save(context)
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
        if added > 0 { Persistence.save(context) }
        return added
    }

    @discardableResult
    func deleteCard(id: UUID) -> Bool {
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        guard let card = try? context.fetch(descriptor).first,
              decks().first(where: { $0.id == card.deckID })?.kind == .user else { return false }
        delete(cards: [card])
        Persistence.save(context)
        return true
    }

    func reviewStats(now: Date) -> StudyStats {
        // Only the dates are needed for the streak; a partial fetch skips the other columns.
        var descriptor = FetchDescriptor<ReviewLog>()
        descriptor.propertiesToFetch = [\.reviewedAt]
        let logs = (try? context.fetch(descriptor)) ?? []
        return StudyStatsCalculator.stats(reviewDates: logs.map(\.reviewedAt), now: now)
    }

    func deleteDeck(id: UUID) {
        let descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
        guard let deck = try? context.fetch(descriptor).first else { return }
        delete(cards: cards(inDeck: id))
        context.delete(deck)
        Persistence.save(context)
    }

    @discardableResult
    func record(cardID: UUID, grade: SRSGrade, now: Date) -> SRSState? {
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == cardID })
        guard let card = try? context.fetch(descriptor).first else { return nil }
        let previous = card.srs
        let updated = scheduler.next(previous, grade: grade, now: now)
        card.srs = updated
        context.insert(ReviewLog(cardID: cardID, grade: grade, reviewedAt: now, prevInterval: previous.interval, newInterval: updated.interval))
        Persistence.save(context)
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
        Persistence.save(context)
    }

    // MARK: - Backup

    func backup() -> StudyBackup {
        var result = StudyBackup()
        let allDecks = decks()
        var included = Set<UUID>()
        for deck in allDecks where deck.kind == .user {
            result.decks.append(.init(id: deck.id, name: deck.name, createdAt: deck.createdAt))
            for card in cards(inDeck: deck.id) {
                result.cards.append(.init(id: card.id, deckID: deck.id, front: card.front, back: card.back, createdAt: card.createdAt, srs: .init(card.srs)))
                included.insert(card.id)
            }
        }
        if let vocabulary = allDecks.first(where: { $0.kind == .vocabulary }) {
            for card in cards(inDeck: vocabulary.id) where card.phase != .new {
                guard let word = card.sourceWordID else { continue }
                result.vocabulary.append(.init(cardID: card.id, wordID: word, srs: .init(card.srs)))
                included.insert(card.id)
            }
        }
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)]))) ?? []
        for log in logs where included.contains(log.cardID) {
            result.logs.append(.init(id: log.id, cardID: log.cardID, grade: log.gradeRaw, reviewedAt: log.reviewedAt, prevInterval: log.prevInterval, newInterval: log.newInterval))
        }
        return result
    }

    func restore(_ backup: StudyBackup, wordIDMap: [UUID: UUID]) throws -> StudyRestoreResult {
        var result = StudyRestoreResult()
        let existingDecks = decks().filter { $0.kind == .user }
        var deckByArchivedID: [UUID: Deck] = [:]
        for record in backup.decks {
            if let same = existingDecks.first(where: { $0.id == record.id }) {
                deckByArchivedID[record.id] = same
            } else if let named = existingDecks.first(where: { $0.name.caseInsensitiveCompare(record.name) == .orderedSame }) {
                deckByArchivedID[record.id] = named
            } else {
                let name = String(record.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                let deck = Deck(name: name.isEmpty ? "Deck" : name, kind: .user, createdAt: record.createdAt)
                if !deckIDTaken(record.id) { deck.id = record.id }
                context.insert(deck)
                deckByArchivedID[record.id] = deck
                result.decks += 1
            }
        }

        func normalized(_ front: String, _ back: String) -> String { "\(front.lowercased())\u{1F}\(back.lowercased())" }
        var existingByDeck: [UUID: [String: Card]] = [:]
        for card in backup.cards {
            guard let deck = deckByArchivedID[card.deckID] else { continue }
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            if existingByDeck[deck.id] == nil {
                existingByDeck[deck.id] = Dictionary(cards(inDeck: deck.id).map { (normalized($0.front, $0.back), $0) }, uniquingKeysWith: { first, _ in first })
            }
            let key = normalized(front, back)
            let state = card.srs.state
            if let existing = existingByDeck[deck.id]?[key] {
                result.cardIDMap[card.id] = existing.id
                if existing.phase == .new, state.phase != .new {
                    existing.srs = state
                    result.progress += 1
                }
            } else {
                let created = Card(deckID: deck.id, front: front, back: back, createdAt: card.createdAt)
                if !cardIDTaken(card.id) { created.id = card.id }
                created.srs = state
                context.insert(created)
                existingByDeck[deck.id]?[key] = created
                result.cardIDMap[card.id] = created.id
                result.cards += 1
            }
        }

        if !backup.vocabulary.isEmpty, let vocabulary = decks().first(where: { $0.kind == .vocabulary }) {
            var bySource: [UUID: Card] = [:]
            for card in cards(inDeck: vocabulary.id) {
                if let source = card.sourceWordID, bySource[source] == nil { bySource[source] = card }
            }
            for entry in backup.vocabulary {
                guard let card = bySource[wordIDMap[entry.wordID] ?? entry.wordID] else { continue }
                result.cardIDMap[entry.cardID] = card.id
                let state = entry.srs.state
                if card.phase == .new, state.phase != .new {
                    card.srs = state
                    result.progress += 1
                }
            }
        }
        guard Persistence.save(context) else {
            context.rollback()
            throw PersistenceError.saveFailed
        }
        return result
    }

    func restoreLogs(_ logs: [StudyBackup.LogRecord], cardIDMap: [UUID: UUID]) throws -> Int {
        let usable = logs.filter { cardIDMap[$0.cardID] != nil }
        guard !usable.isEmpty else { return 0 }
        var known = Set<UUID>()
        for chunk in Self.chunks(usable.map(\.id)) {
            let found = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { chunk.contains($0.id) }))) ?? []
            known.formUnion(found.map(\.id))
        }
        var added = 0
        for record in usable where !known.contains(record.id) {
            guard let cardID = cardIDMap[record.cardID] else { continue }
            let log = ReviewLog(cardID: cardID, grade: SRSGrade(rawValue: record.grade) ?? .again, reviewedAt: record.reviewedAt, prevInterval: max(0, record.prevInterval), newInterval: max(0, record.newInterval))
            log.id = record.id
            context.insert(log)
            known.insert(record.id)
            added += 1
        }
        guard Persistence.save(context) else {
            context.rollback()
            throw PersistenceError.saveFailed
        }
        return added
    }

    // MARK: - Helpers

    /// `id` is unique in every model: reusing an archived id that is taken would replace the other record.
    private func deckIDTaken(_ id: UUID) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
    }

    private func cardIDTaken(_ id: UUID) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Card>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
    }

    private func count<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Cards whose first-ever review happened on or after `start`. Only today's logs are loaded, plus the older
    /// logs of the cards reviewed today (to tell a first review from a repeat).
    private func newCardsStudied(since start: Date) -> Int {
        let today = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt >= start }))) ?? []
        let todayIDs = Array(Set(today.map(\.cardID)))
        guard !todayIDs.isEmpty else { return 0 }
        var seenBefore = Set<UUID>()
        for chunk in Self.chunks(todayIDs) {
            let older = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt < start && chunk.contains($0.cardID) }))) ?? []
            seenBefore.formUnion(older.map(\.cardID))
        }
        return Set(todayIDs).subtracting(seenBefore).count
    }

    private func delete(cards: [Card]) {
        guard !cards.isEmpty else { return }
        for chunk in Self.chunks(cards.map(\.id)) {
            for log in (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { chunk.contains($0.cardID) }))) ?? [] {
                context.delete(log)
            }
        }
        for card in cards { context.delete(card) }
    }

    /// Keeps an `IN (...)` list well under SQLite's variable limit.
    private static func chunks(_ ids: [UUID], size: Int = 200) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }
}
