import Foundation
import SwiftData

enum ReviewLimits {
    static let maxNoteLength = 200
    static let maxTextLength = 200
}

/// One request to flag a word. Plain values: the caller (the app layer) resolves the word.
struct ReviewFlag {
    var wordID: UUID
    var headword: String
    var translation: String
    var score: Double
    var note: String
    var sourceArtifactID: UUID?
}

/// Hides SwiftData behind a small protocol, like `WordRepository` and `ArtifactRepository`.
@MainActor
protocol ReviewRepository {
    /// Upserts onto the word's open need: `flagCount += 1`, `score = max`, note and source refreshed.
    /// Without an open need, creates one. Returns how many entries were applied.
    @discardableResult
    func flag(_ entries: [ReviewFlag], now: Date) -> Int
    /// Highest score first, then most recently updated.
    func openNeeds() -> [ReviewNeed]
    func openNeed(wordID: UUID) -> ReviewNeed?
    func openCount() -> Int
    /// The person says they learned it: the need is cleared (kept as history).
    func markLearned(id: UUID, now: Date)
    /// Deletes every need (open or cleared) whose word is no longer in `validWordIDs`.
    func deleteOrphans(validWordIDs: Set<UUID>)
}

@MainActor
final class SwiftDataReviewRepository: ReviewRepository {
    private let context: ModelContext
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    /// A private in-memory store: the default for tests and previews that don't care about review needs.
    static func inMemory() -> SwiftDataReviewRepository {
        let container = try! ModelContainer(for: Schema([ReviewNeed.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataReviewRepository(context: ModelContext(container), retaining: container)
    }

    private func clean(_ text: String, limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    @discardableResult
    func flag(_ entries: [ReviewFlag], now: Date) -> Int {
        var applied = 0
        for entry in entries {
            let score = entry.score.isFinite ? min(max(entry.score, 0), 1) : 0.5
            let note = clean(entry.note, limit: ReviewLimits.maxNoteLength)
            if let existing = openNeed(wordID: entry.wordID) {
                existing.flagCount += 1
                existing.score = max(existing.score, score)
                existing.note = note
                existing.sourceArtifactID = entry.sourceArtifactID
                existing.headword = clean(entry.headword, limit: ReviewLimits.maxTextLength)
                existing.translation = clean(entry.translation, limit: ReviewLimits.maxTextLength)
                existing.updatedAt = now
            } else {
                context.insert(ReviewNeed(
                    wordID: entry.wordID,
                    headword: clean(entry.headword, limit: ReviewLimits.maxTextLength),
                    translation: clean(entry.translation, limit: ReviewLimits.maxTextLength),
                    score: score,
                    note: note,
                    sourceArtifactID: entry.sourceArtifactID,
                    now: now
                ))
            }
            applied += 1
        }
        try? context.save()
        return applied
    }

    func openNeeds() -> [ReviewNeed] {
        let open = ReviewStatus.open.rawValue
        let descriptor = FetchDescriptor<ReviewNeed>(predicate: #Predicate { $0.statusRaw == open })
        let all = (try? context.fetch(descriptor)) ?? []
        return all.sorted { $0.score != $1.score ? $0.score > $1.score : $0.updatedAt > $1.updatedAt }
    }

    func openNeed(wordID: UUID) -> ReviewNeed? {
        let open = ReviewStatus.open.rawValue
        let descriptor = FetchDescriptor<ReviewNeed>(predicate: #Predicate { $0.wordID == wordID && $0.statusRaw == open })
        return try? context.fetch(descriptor).first
    }

    func openCount() -> Int {
        let open = ReviewStatus.open.rawValue
        let descriptor = FetchDescriptor<ReviewNeed>(predicate: #Predicate { $0.statusRaw == open })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func markLearned(id: UUID, now: Date) {
        let descriptor = FetchDescriptor<ReviewNeed>(predicate: #Predicate { $0.id == id })
        guard let need = try? context.fetch(descriptor).first, need.status == .open else { return }
        need.status = .cleared
        need.clearedAt = now
        need.updatedAt = now
        try? context.save()
    }

    func deleteOrphans(validWordIDs: Set<UUID>) {
        let all = (try? context.fetch(FetchDescriptor<ReviewNeed>())) ?? []
        var changed = false
        for need in all where !validWordIDs.contains(need.wordID) {
            context.delete(need)
            changed = true
        }
        if changed { try? context.save() }
    }
}
