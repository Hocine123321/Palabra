import Foundation

enum ChatPrompts {
    /// Action lines of the transcript start with this; the stub AI relies on it too.
    static let actionLinePrefix = "  ["
    static let transcriptBudget = 24_000

    static func systemInstruction(manual: String, language: SupportedLanguage, linkedWord: (id: UUID, title: String)?) -> String {
        var text = """
        You are the assistant inside Palabra, an iPhone app for learning Spanish vocabulary. You help the user learn Spanish and manage their word library, flashcard decks and review list.

        Reply in \(language.instructionName) unless the user writes in another language; keep Spanish words in Spanish. Be warm, concise and practical. Short paragraphs; light Markdown (bold, lists) is fine.

        You can act on the app through these capabilities:
        \(manual)

        How to act: write your reply text first. When you need a capability, then add a line containing exactly \(ChatReplyParser.marker) followed by a JSON array of calls, for example:
        \(ChatReplyParser.marker)
        [{"capability":"library.words","args":{"limit":20}}]
        Leave the marker out when you need no capability.

        Rules:
        - Read capabilities run immediately and you then receive their results to continue. Write capabilities are first shown to the user, who approves or declines; you receive the outcome afterwards.
        - Never invent ids, keys or data. Read first (library.words, study.decks, review.list) to get what you need.
        - Only propose a write when the user asked for it or clearly agreed. Prefer one call with several items over many calls. At most \(ChatLimits.maxCallsPerReply) calls per reply.
        - Before the marker, say in plain words what you are about to do. Never show the JSON or capability names to the user.
        - When results arrive, summarize what happened, including anything that failed or was skipped. Do not repeat a call that failed with notGranted or unknown.
        """
        if let linkedWord {
            text += "\n\nThe user opened this chat from the word \"\(linkedWord.title)\" (id \(linkedWord.id.uuidString)). Questions without another subject are about that word; call library.word with that id when you need its full explanation."
        }
        return text
    }

    /// The conversation as text (the client has no multi-turn API): newest turns win when over budget.
    static func transcript(turns: [ChatTurn], budget: Int = transcriptBudget) -> String {
        var blocks: [String] = []
        for turn in turns where turn.status == .sent {
            switch turn.role {
            case .user:
                blocks.append("USER: \(turn.text)")
            case .assistant:
                var block = "ASSISTANT: \(turn.text)"
                for action in turn.actions { block += "\n" + line(for: action) }
                blocks.append(block)
            }
        }
        var kept: [String] = []
        var size = 0
        for block in blocks.reversed() {
            if size + block.count > budget, !kept.isEmpty { break }
            kept.append(block)
            size += block.count + 1
        }
        return "CONVERSATION:\n" + kept.reversed().joined(separator: "\n") + "\n\nWrite the next ASSISTANT reply now."
    }

    static func line(for action: ChatAction) -> String {
        let head = "\(actionLinePrefix)\(action.isWrite ? "write" : "read") \(action.capability) \(action.argsJSON)]"
        switch action.state {
        case .pending: return "\(head) -> waiting for the user's approval"
        case .applied: return "\(head) -> applied: \(action.result ?? "ok")"
        case .declined: return "\(head) -> declined by the user"
        case .failed: return "\(head) -> failed: \(action.result ?? "unknown error")"
        }
    }

    static func retryAddendum(_ problem: String) -> String {
        "\n\nYour previous reply could not be used: \(problem). Reply again. The part after \(ChatReplyParser.marker) must be a JSON array of {\"capability\": \"name\", \"args\": {…}}."
    }
}
