import Foundation

/// Turns stored chat messages into the alternating user/assistant history the
/// API expects: failed messages excluded, capped to the most recent `limit`,
/// consecutive same-role messages merged so roles strictly alternate.
enum ChatHistoryBuilder {
    struct Turn: Equatable, Sendable {
        var role: ChatMessage.Role
        var text: String
    }

    static func build(from messages: [ChatMessage], limit: Int = 20) -> [Turn] {
        let usable = messages.filter { $0.status == .sent }.suffix(limit)
        var turns: [Turn] = []
        for message in usable {
            if let last = turns.indices.last, turns[last].role == message.role {
                turns[last].text += "\n\n" + message.text
            } else {
                turns.append(Turn(role: message.role, text: message.text))
            }
        }
        return turns
    }
}
