import Foundation
import SwiftData

/// Hides SwiftData behind a small protocol, like the other repositories.
@MainActor
protocol SolveRepository {
    /// Most recently used first.
    func entries(limit: Int) -> [SolveEntry]
    func entry(id: UUID) -> SolveEntry?
    func entry(forKey key: String) -> SolveEntry?
    /// Inserts, or replaces the stored result of the entry with the same key (and bumps it to the top).
    @discardableResult
    func save(query: String, key: String, result: SolveResult, now: Date) -> SolveEntry
    /// Replaces the stored result (for example after steps were added) without moving the entry.
    func update(id: UUID, result: SolveResult, now: Date)
    func delete(id: UUID)
    func deleteAll()
}

@MainActor
final class SwiftDataSolveRepository: SolveRepository {
    /// Oldest entries beyond this are dropped.
    static let maxEntries = 200

    private let context: ModelContext
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    static func inMemory() -> SwiftDataSolveRepository {
        let container = try! ModelContainer(for: Schema([SolveEntry.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataSolveRepository(context: ModelContext(container), retaining: container)
    }

    func entries(limit: Int) -> [SolveEntry] {
        var descriptor = FetchDescriptor<SolveEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = max(0, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    func entry(id: UUID) -> SolveEntry? {
        try? context.fetch(FetchDescriptor<SolveEntry>(predicate: #Predicate { $0.id == id })).first
    }

    func entry(forKey key: String) -> SolveEntry? {
        try? context.fetch(FetchDescriptor<SolveEntry>(predicate: #Predicate { $0.queryKey == key })).first
    }

    @discardableResult
    func save(query: String, key: String, result: SolveResult, now: Date) -> SolveEntry {
        let data = (try? JSONEncoder().encode(result)) ?? Data()
        let entry: SolveEntry
        if let existing = self.entry(forKey: key) {
            existing.query = query
            existing.resultData = data
            existing.updatedAt = now
            entry = existing
        } else {
            entry = SolveEntry(query: query, queryKey: key, resultData: data, now: now)
            context.insert(entry)
        }
        trim()
        try? context.save()
        return entry
    }

    func update(id: UUID, result: SolveResult, now: Date) {
        guard let entry = entry(id: id), let data = try? JSONEncoder().encode(result) else { return }
        entry.resultData = data
        try? context.save()
    }

    func delete(id: UUID) {
        guard let entry = entry(id: id) else { return }
        context.delete(entry)
        try? context.save()
    }

    func deleteAll() {
        for entry in (try? context.fetch(FetchDescriptor<SolveEntry>())) ?? [] { context.delete(entry) }
        try? context.save()
    }

    private func trim() {
        let all = entries(limit: Int.max)
        guard all.count > Self.maxEntries else { return }
        for entry in all.dropFirst(Self.maxEntries) { context.delete(entry) }
    }
}
