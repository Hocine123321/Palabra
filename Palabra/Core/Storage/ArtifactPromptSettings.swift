import Foundation

/// The person's changes to the prompts that make an artifact compatible with Palabra. Everything here is optional: an
/// empty value means "the built-in text", so a fresh install, an old saved setting and "Reset" all mean the same thing.
///  - the prompt copied into another AI (Claude, ChatGPT): intro, each built-in rule (switch off or reword), extra rules,
///    whether the capability list is included, or the whole prompt replaced by a template;
///  - the in-app AI (Gemini): extra rules, or the whole instruction replaced by a template. Its output format is not
///    optional (the app reads the answer by it), so a template that leaves it out gets it appended.
struct ArtifactPromptSettings: Codable, Equatable, Sendable {
    struct RuleOverride: Codable, Equatable, Sendable {
        var enabled = true
        /// nil = the built-in wording.
        var text: String?

        init(enabled: Bool = true, text: String? = nil) {
            self.enabled = enabled
            self.text = text
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
            text = ArtifactPromptSettings.clean(try? c.decodeIfPresent(String.self, forKey: .text))
        }
    }

    /// No single text is longer than this (a prompt is a page of rules, not a book).
    static let maxLength = 20_000

    // The prompt copied into another AI.
    var intro: String?
    /// Keyed by `ArtifactPromptRule.rawValue`; a rule with no entry is on with its built-in wording.
    var rules: [String: RuleOverride] = [:]
    /// One rule per line, added after the built-in ones.
    var extraRules = ""
    var includeCapabilities = true
    /// Replaces the whole prompt when set (placeholders such as {{REQUEST}} are filled in).
    var template: String?

    // The in-app AI.
    var inAppExtraRules = ""
    var inAppTemplate: String?

    static let `default` = ArtifactPromptSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intro = Self.clean(try? c.decodeIfPresent(String.self, forKey: .intro))
        let decoded = (try? c.decodeIfPresent([String: RuleOverride].self, forKey: .rules)) ?? [:]
        rules = decoded.filter { !$0.value.enabled || $0.value.text != nil }
        extraRules = Self.clean(try? c.decodeIfPresent(String.self, forKey: .extraRules)) ?? ""
        includeCapabilities = (try? c.decodeIfPresent(Bool.self, forKey: .includeCapabilities)) ?? true
        template = Self.clean(try? c.decodeIfPresent(String.self, forKey: .template))
        inAppExtraRules = Self.clean(try? c.decodeIfPresent(String.self, forKey: .inAppExtraRules)) ?? ""
        inAppTemplate = Self.clean(try? c.decodeIfPresent(String.self, forKey: .inAppTemplate))
    }

    /// Trimmed, capped, and nil when blank.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }

    /// What is actually in force: a text that is only spaces counts as "not set" (the editor keeps what is being typed as is).
    var activeIntro: String? { Self.nonBlank(intro) }
    var activeTemplate: String? { Self.nonBlank(template) }
    var activeInAppTemplate: String? { Self.nonBlank(inAppTemplate) }
    var activeExtraRules: String { Self.nonBlank(extraRules) ?? "" }
    var activeInAppExtraRules: String { Self.nonBlank(inAppExtraRules) ?? "" }

    static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// True when nothing is changed from the built-in prompts.
    var isDefault: Bool { !changesExternalPrompt && !changesInAppPrompt }

    /// Whether the external prompt differs from the built-in one.
    var changesExternalPrompt: Bool {
        activeIntro != nil || !rules.isEmpty || !activeExtraRules.isEmpty || !includeCapabilities || activeTemplate != nil
    }

    var changesInAppPrompt: Bool { !activeInAppExtraRules.isEmpty || activeInAppTemplate != nil }

    func override(for ruleID: String) -> RuleOverride { rules[ruleID] ?? RuleOverride() }

    mutating func setRule(_ id: String, enabled: Bool, text: String?) {
        let value = RuleOverride(enabled: enabled, text: Self.nonBlank(text).map { String($0.prefix(Self.maxLength)) })
        if value.enabled && value.text == nil { rules[id] = nil } else { rules[id] = value }
    }
}
