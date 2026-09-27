import Foundation
import SwiftData

/// Hides SwiftData behind a small protocol, matching `WordRepository`'s shape.
@MainActor
protocol FlashcardRepository {
    @discardableResult
    func insert(subject: String, front: String, back: String, hint: String?) -> Flashcard
    func review(id: UUID, grade: SpacedRepetition.Grade, now: Date)
    func delete(id: UUID)
    func allCards() -> [Flashcard]
    func dueCards(subject: String?, now: Date) -> [Flashcard]
    func subjects() -> [String]
}

@MainActor
final class SwiftDataFlashcardRepository: FlashcardRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func insert(subject: String, front: String, back: String, hint: String? = nil) -> Flashcard {
        let card = Flashcard(subject: subject, front: front, back: back, hint: hint)
        context.insert(card)
        try? context.save()
        return card
    }

    func review(id: UUID, grade: SpacedRepetition.Grade, now: Date = Date()) {
        guard let card = fetchByID(id) else { return }
        card.reviewState = SpacedRepetition.schedule(card.reviewState, grade: grade, now: now)
        try? context.save()
    }

    func delete(id: UUID) {
        guard let card = fetchByID(id) else { return }
        context.delete(card)
        try? context.save()
    }

    func allCards() -> [Flashcard] {
        let descriptor = FetchDescriptor<Flashcard>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func dueCards(subject: String? = nil, now: Date = Date()) -> [Flashcard] {
        allCards()
            .filter { $0.dueDate <= now }
            .filter { subject == nil || $0.subject == subject }
            .sorted { $0.dueDate < $1.dueDate }
    }

    func subjects() -> [String] {
        Array(Set(allCards().map(\.subject))).sorted()
    }

    private func fetchByID(_ id: UUID) -> Flashcard? {
        let descriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
