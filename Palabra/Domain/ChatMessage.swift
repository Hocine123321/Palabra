import Foundation

/// One turn in the per-word AI conversation.
struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var role: Role
    var text: String
    var createdAt: Date
    var status: Status
    var errorText: String?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum Status: String, Codable, Sendable {
        case sent
        case failed
    }

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date(), status: Status = .sent, errorText: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.status = status
        self.errorText = errorText
    }
}
