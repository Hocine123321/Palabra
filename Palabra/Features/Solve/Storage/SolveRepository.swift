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
    /// `image` is the photo of a problem solved from a picture; without one, a photo already saved with the entry stays.
    @discardableResult
    func save(query: String, key: String, result: SolveResult, image: Data?, now: Date) -> SolveEntry
    /// The saved photo of a problem solved from a picture.
    func problemImage(id: UUID) -> Data?
    /// Replaces the stored result (for example after steps were added) without moving the entry.
    func update(id: UUID, result: SolveResult, now: Date)
    func delete(id: UUID)
    func deleteAll()
}

extension SolveRepository {
    @discardableResult
    func save(query: String, key: String, result: SolveResult, now: Date) -> SolveEntry {
        save(query: query, key: key, result: result, image: nil, now: now)
    }
}

@MainActor
final class SwiftDataSolveRepository: SolveRepository {
    /// Oldest entries beyond this are dropped.
    static let maxEntries = 200

    private let context: ModelContext
    private let retainedContainer: ModelContainer?
    private let images: SolveImageStore

    init(context: ModelContext, retaining container: ModelContainer? = nil, images: SolveImageStore = .standard()) {
        self.context = context
        self.retainedContainer = container
        self.images = images
    }

    static func inMemory(images: SolveImageStore = .temporary()) -> SwiftDataSolveRepository {
        let container = try! ModelContainer(for: Schema([SolveEntry.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataSolveRepository(context: ModelContext(container), retaining: container, images: images)
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
    func save(query: String, key: String, result: SolveResult, image: Data?, now: Date) -> SolveEntry {
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
        if let image { images.write(image, for: entry.id) }
        trim()
        Persistence.save(context)
        return entry
    }

    func problemImage(id: UUID) -> Data? { images.data(for: id) }

    func update(id: UUID, result: SolveResult, now: Date) {
        guard let entry = entry(id: id), let data = try? JSONEncoder().encode(result) else { return }
        entry.resultData = data
        Persistence.save(context)
    }

    func delete(id: UUID) {
        guard let entry = entry(id: id) else { return }
        context.delete(entry)
        images.remove(id)
        Persistence.save(context)
    }

    func deleteAll() {
        for entry in (try? context.fetch(FetchDescriptor<SolveEntry>())) ?? [] { context.delete(entry) }
        images.removeAll()
        Persistence.save(context)
    }

    private func trim() {
        let all = entries(limit: Int.max)
        guard all.count > Self.maxEntries else { return }
        for entry in all.dropFirst(Self.maxEntries) {
            images.remove(entry.id)
            context.delete(entry)
        }
    }
}
