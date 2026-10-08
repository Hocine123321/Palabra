import Foundation
import SwiftData

/// Hides SwiftData behind a small protocol, like `WordRepository`, so
/// `AddWordFlow` and `WordQueueProcessor` depend on this, not `ModelContext`.
@MainActor
protocol WordQueueRepository {
    @discardableResult
    func enqueue(inputWord: String, mode: AddWordFlow.Mode, language: SupportedLanguage) -> WordQueueItem
    /// Every queued item, oldest first.
    func allItems() -> [WordQueueItem]
    /// The oldest `.pending` item, if any — what `WordQueueProcessor` should try next.
    func nextPending() -> WordQueueItem?
    func markProcessing(id: UUID)
    /// Back to `.pending`, e.g. after an offline attempt or to retry a failed one.
    func markPending(id: UUID, attempts: Int, lastError: String?)
    func markFailed(id: UUID, lastError: String)
    func remove(id: UUID)
    /// Resets any item still `.processing` back to `.pending`. Nothing can
    /// genuinely still be in flight when this is called — `WordQueueProcessor`
    /// calls it once at the start of a fresh drain, when no other drain is
    /// running — so a `.processing` item found here is orphaned, left that
    /// way by the app being killed mid-request in an earlier session.
    func resetStuckProcessing()
}

@MainActor
final class SwiftDataWordQueueRepository: WordQueueRepository {
    private let context: ModelContext
    /// Keeps an in-memory container alive when this repository owns it.
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    /// A private in-memory store: the default for tests and previews that don't care about the queue.
    static func inMemory() -> SwiftDataWordQueueRepository {
        let container = try! ModelContainer(for: Schema([WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataWordQueueRepository(context: ModelContext(container), retaining: container)
    }

    @discardableResult
    func enqueue(inputWord: String, mode: AddWordFlow.Mode, language: SupportedLanguage) -> WordQueueItem {
        let item = WordQueueItem(inputWord: inputWord, mode: mode, language: language)
        context.insert(item)
        try? context.save()
        return item
    }

    func allItems() -> [WordQueueItem] {
        let descriptor = FetchDescriptor<WordQueueItem>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func nextPending() -> WordQueueItem? {
        allItems().first { $0.status == .pending }
    }

    func markProcessing(id: UUID) {
        guard let item = fetchByID(id) else { return }
        item.status = .processing
        try? context.save()
    }

    func markPending(id: UUID, attempts: Int, lastError: String?) {
        guard let item = fetchByID(id) else { return }
        item.status = .pending
        item.attempts = attempts
        item.lastErrorMessage = lastError
        try? context.save()
    }

    func markFailed(id: UUID, lastError: String) {
        guard let item = fetchByID(id) else { return }
        item.status = .failed
        item.lastErrorMessage = lastError
        try? context.save()
    }

    func remove(id: UUID) {
        guard let item = fetchByID(id) else { return }
        context.delete(item)
        try? context.save()
    }

    func resetStuckProcessing() {
        for item in allItems() where item.status == .processing {
            item.status = .pending
        }
        try? context.save()
    }

    private func fetchByID(_ id: UUID) -> WordQueueItem? {
        let descriptor = FetchDescriptor<WordQueueItem>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
