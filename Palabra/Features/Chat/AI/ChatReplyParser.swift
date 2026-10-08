import Foundation

/// One capability call the assistant asked for.
struct ChatCall: Equatable {
    var capability: String
    var args: JSONValue
}

struct ChatReply: Equatable {
    /// What the person reads.
    var say: String
    var calls: [ChatCall]
}

enum ChatParseError: Error, Equatable {
    /// The `---ACTIONS---` block was not a JSON array of `{capability, args}`.
    case malformedActions(String)

    var detail: String {
        switch self {
        case .malformedActions(let problem): return problem
        }
    }
}

/// Parses `reply text`, then optionally a line `---ACTIONS---` and a JSON array of calls.
enum ChatReplyParser {
    static let marker = "---ACTIONS---"

    static func parse(_ raw: String) -> Result<ChatReply, ChatParseError> {
        let lines = raw.components(separatedBy: "\n")
        guard let markerIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker }) else {
            return .success(ChatReply(say: raw.trimmingCharacters(in: .whitespacesAndNewlines), calls: []))
        }
        let say = lines[..<markerIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let block = CodeFence.strip(lines[(markerIndex + 1)...].joined(separator: "\n"))
        if block.isEmpty { return .success(ChatReply(say: say, calls: [])) }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(block.utf8)), let items = value.arrayValue else {
            return .failure(.malformedActions("the part after \(marker) is not a JSON array"))
        }
        var calls: [ChatCall] = []
        for item in items.prefix(ChatLimits.maxCallsPerReply) {
            guard let object = item.objectValue, let name = object["capability"]?.stringValue, !name.isEmpty else {
                return .failure(.malformedActions("every call needs a \"capability\" name"))
            }
            let args = object["args"] ?? .object([:])
            guard args.objectValue != nil || args == .null else {
                return .failure(.malformedActions("\"args\" of \(name) must be an object"))
            }
            calls.append(ChatCall(capability: name, args: args == .null ? .object([:]) : args))
        }
        return .success(ChatReply(say: say, calls: calls))
    }

    /// Fallback when the actions block cannot be used: just the reply text, no calls.
    static func textOnly(_ raw: String) -> ChatReply {
        let lines = raw.components(separatedBy: "\n")
        let end = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker }) ?? lines.count
        return ChatReply(say: lines[..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), calls: [])
    }
}
