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
        try? context.save()
        return conversation
    }

    func save(id: UUID, turns: [ChatTurn], title: String?, now: Date) {
        guard let conversation = conversation(id: id) else { return }
        conversation.turns = Self.trimmed(turns)
        if let title { conversation.title = Self.cleanTitle(title) }
        conversation.updatedAt = now
        try? context.save()
    }

    func delete(id: UUID) {
        guard let conversation = conversation(id: id) else { return }
        context.delete(conversation)
        try? context.save()
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
