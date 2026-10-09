import Foundation

/// Which part of the app a chat capability belongs to. The person can switch a group off in Settings;
/// the assistant then neither sees nor may call its capabilities.
enum AssistantToolGroup: String, Codable, CaseIterable, Sendable {
    case library, words, study, review

    /// Capabilities are grouped by name prefix. `nil` = not covered by a switch (always available).
    static func group(forCapability name: String) -> AssistantToolGroup? {
        switch name.split(separator: ".").first.map(String.init) {
        case "library", "stats": return .library
        case "words": return .words
        case "study": return .study
        case "review": return .review
        default: return nil
        }
    }
}

/// Preferences for the Chat assistant. Plain value type (no UserDefaults) so prompts and tests use it directly.
struct AssistantSettings: Codable, Equatable, Sendable {
    enum ReplyLength: String, Codable, CaseIterable, Sendable {
        case concise, balanced, detailed

        var promptHint: String {
            switch self {
            case .concise: return "Keep replies very short: one to three sentences unless the user asks for more."
            case .balanced: return "Keep replies compact: short paragraphs, no filler."
            case .detailed: return "Explain thoroughly: give nuance, several examples and usage notes when they help."
            }
        }
    }

    static let maxInstructionsLength = 500

    var replyLength: ReplyLength = .balanced
    /// On: every change the assistant proposes waits for a tap. Off: changes are applied at once.
    var askBeforeChanging: Bool = true
    /// Groups the assistant may not use. Stored as the *disabled* ones so a future group defaults to on.
    var disabledGroups: Set<AssistantToolGroup> = []
    /// Optional standing instructions, e.g. "always add an example sentence".
    var customInstructions: String = ""

    static let `default` = AssistantSettings()

    init() {}

    /// Tolerant: missing keys and unknown group names (older or newer saved settings) fall back instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AssistantSettings()
        replyLength = (try? c.decodeIfPresent(ReplyLength.self, forKey: .replyLength)) ?? d.replyLength
        askBeforeChanging = try c.decodeIfPresent(Bool.self, forKey: .askBeforeChanging) ?? d.askBeforeChanging
        let raw = try c.decodeIfPresent([String].self, forKey: .disabledGroups) ?? []
        disabledGroups = Set(raw.compactMap(AssistantToolGroup.init(rawValue:)))
        customInstructions = Self.cleaned(try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? "")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(replyLength, forKey: .replyLength)
        try c.encode(askBeforeChanging, forKey: .askBeforeChanging)
        try c.encode(disabledGroups.map(\.rawValue).sorted(), forKey: .disabledGroups)
        try c.encode(customInstructions, forKey: .customInstructions)
    }

    private enum CodingKeys: String, CodingKey {
        case replyLength, askBeforeChanging, disabledGroups, customInstructions
    }

    func isEnabled(_ group: AssistantToolGroup) -> Bool { !disabledGroups.contains(group) }

    func allows(capability name: String) -> Bool {
        guard let group = AssistantToolGroup.group(forCapability: name) else { return true }
        return isEnabled(group)
    }

    mutating func set(_ group: AssistantToolGroup, enabled: Bool) {
        if enabled { disabledGroups.remove(group) } else { disabledGroups.insert(group) }
    }

    static func cleaned(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxInstructionsLength))
    }
}
