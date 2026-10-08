import Foundation
import SwiftData

enum ChatLimits {
    static let maxTurns = 200
    static let maxTextLength = 8_000
    /// A stored capability result (what the AI saw).
    static let maxResultLength = 3_000
    static let maxCallsPerReply = 5
    static let maxRoundsPerMessage = 4
    static let maxTitleLength = 40
}

/// One thing the assistant did (a read, already run) or proposes to do (a write, waiting for the person).
struct ChatAction: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case applied
        case declined
        case failed
    }

    var id: UUID
    var capability: String
    /// Compact JSON of the arguments, so a pending write survives relaunch.
    var argsJSON: String
    /// Plain-language line for the confirmation card.
    var summary: String
    var isWrite: Bool
    var state: State
    /// Compact JSON result, or the error text when `state == .failed`.
    var result: String?

    init(id: UUID = UUID(), capability: String, argsJSON: String, summary: String, isWrite: Bool, state: State, result: String? = nil) {
        self.id = id
        self.capability = capability
        self.argsJSON = argsJSON
        self.summary = summary
        self.isWrite = isWrite
        self.state = state
        self.result = result
    }
}

/// One message in a conversation. Stored as JSON inside `ChatConversation`, with tolerant decoding
/// so adding fields later never loses saved chats.
struct ChatTurn: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum Status: String, Codable, Sendable {
        case sent
        case failed
    }

    var id: UUID
    var role: Role
    var text: String
    var createdAt: Date
    var status: Status
    var errorText: String?
    var actions: [ChatAction]

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date(), status: Status = .sent, errorText: String? = nil, actions: [ChatAction] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.status = status
        self.errorText = errorText
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey { case id, role, text, createdAt, status, errorText, actions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .assistant
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .sent
        errorText = try c.decodeIfPresent(String.self, forKey: .errorText)
        actions = try c.decodeIfPresent([ChatAction].self, forKey: .actions) ?? []
    }
}

/// A saved chat. New SwiftData entity: stored property names are append-only once shipped.
/// Messages live in one JSON blob (like `Word.chatData`), referenced by nothing else.
@Model
final class ChatConversation {
    static let defaultTitle = "New chat"

    @Attribute(.unique) var id: UUID
    var title: String
    /// Set when the chat was opened from a word's page.
    var wordID: UUID?
    var turnsData: Data
    var createdAt: Date
    var updatedAt: Date

    init(title: String, wordID: UUID?, turns: [ChatTurn], now: Date) {
        id = UUID()
        self.title = title
        self.wordID = wordID
        turnsData = (try? JSONEncoder().encode(turns)) ?? Data("[]".utf8)
        createdAt = now
        updatedAt = now
    }

    var turns: [ChatTurn] {
        get { (try? JSONDecoder().decode([ChatTurn].self, from: turnsData)) ?? [] }
        set { turnsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}
