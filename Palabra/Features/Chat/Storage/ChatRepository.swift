import Foundation
import SwiftData

/// Hides SwiftData behind a small protocol, like the other repositories.
@MainActor
protocol ChatRepository {
    /// Most recently updated first.
    func conversations() -> [ChatConversation]
    func conversation(id: UUID) -> ChatConversation?
    /// The chat opened from this word, if any.
    func conversation(forWordID id: UUID) -> ChatConversation?
    @discardableResult
    func create(title: String, wordID: UUID?, turns: [ChatTurn], now: Date) -> ChatConversation
    /// Replaces the messages (trimmed to the newest `maxTurns`, texts capped) and touches `updatedAt`.
    func save(id: UUID, turns: [ChatTurn], title: String?, now: Date)
    func delete(id: UUID)
    /// Every conversation as plain values, for a backup.
    func backupConversations() -> [ChatBackup]
    /// Adds the conversations that are not here yet (same id = same chat, left alone). `wordIDMap` re-points a chat to
    /// the word it now has in this library. Returns how many were added. Throws `PersistenceError.saveFailed` when
    /// the batch cannot be written (nothing is added then).
    func restore(_ records: [ChatBackup], wordIDMap: [UUID: UUID]) throws -> Int
}

@MainActor
final class SwiftDataChatRepository: ChatRepository {
    private let context: ModelContext
    private let retainedContainer: ModelContainer?

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        self.context = context
        self.retainedContainer = container
    }

    /// A private in-memory store: the default for tests and previews that don't care about chats.
    static func inMemory() -> SwiftDataChatRepository {
        let container = try! ModelContainer(for: Schema([ChatConversation.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return SwiftDataChatRepository(context: ModelContext(container), retaining: container)
    }

    func conversations() -> [ChatConversation] {
        let descriptor = FetchDescriptor<ChatConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func conversation(id: UUID) -> ChatConversation? {
        let descriptor = FetchDescriptor<ChatConversation>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func conversation(forWordID id: UUID) -> ChatConversation? {
        let descriptor = FetchDescriptor<ChatConversation>(
            predicate: #Predicate { $0.wordID == id },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func create(title: String, wordID: UUID?, turns: [ChatTurn], now: Date) -> ChatConversation {
        let conversation = ChatConversation(title: Self.cleanTitle(title), wordID: wordID, turns: Self.trimmed(turns), now: now)
        context.insert(conversation)
        Persistence.save(context)
        return conversation
    }

    func save(id: UUID, turns: [ChatTurn], title: String?, now: Date) {
        guard let conversation = conversation(id: id) else { return }
        conversation.turns = Self.trimmed(turns)
        if let title { conversation.title = Self.cleanTitle(title) }
        conversation.updatedAt = now
        Persistence.save(context)
    }

    func delete(id: UUID) {
        guard let conversation = conversation(id: id) else { return }
        context.delete(conversation)
        Persistence.save(context)
    }

    func backupConversations() -> [ChatBackup] {
        conversations().map {
            ChatBackup(id: $0.id, title: $0.title, wordID: $0.wordID, turns: $0.turns, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
    }

    func restore(_ records: [ChatBackup], wordIDMap: [UUID: UUID]) throws -> Int {
        var added = 0
        var seen = Set<UUID>()
        for record in records where !seen.contains(record.id) && conversation(id: record.id) == nil {
            seen.insert(record.id)
            let wordID = record.wordID.map { wordIDMap[$0] ?? $0 }
            let conversation = ChatConversation(title: Self.cleanTitle(record.title), wordID: wordID, turns: Self.trimmed(record.turns), now: record.createdAt)
            conversation.id = record.id
            conversation.updatedAt = record.updatedAt
            context.insert(conversation)
            added += 1
        }
        guard added > 0 else { return 0 }
        guard Persistence.save(context) else {
            context.rollback()
            throw PersistenceError.saveFailed
        }
        return added
    }

    private static func cleanTitle(_ raw: String) -> String {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.isEmpty ? ChatConversation.defaultTitle : String(collapsed.prefix(ChatLimits.maxTitleLength))
    }

    private static func trimmed(_ turns: [ChatTurn]) -> [ChatTurn] {
        turns.suffix(ChatLimits.maxTurns).map { turn in
            var copy = turn
            copy.text = String(turn.text.prefix(ChatLimits.maxTextLength))
            copy.actions = turn.actions.map { action in
                var a = action
                if let result = a.result { a.result = String(result.prefix(ChatLimits.maxResultLength)) }
                return a
            }
            return copy
        }
    }
}
