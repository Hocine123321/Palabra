import Foundation

/// User preferences for how the AI organizes the library. Plain value type so
/// it can be passed to prompts and tests without touching UserDefaults.
struct OrganizerSettings: Codable, Equatable, Sendable {
    enum Granularity: String, Codable, CaseIterable, Sendable {
        case broad, balanced, detailed

        /// Target number of sections for a library of typical size.
        var promptHint: String {
            switch self {
            case .broad: return "Use few, broad sections (roughly 4 to 6 in total)."
            case .balanced: return "Use a moderate number of sections (roughly 6 to 10 in total)."
            case .detailed: return "Use more specific sections (roughly 10 to 16 in total)."
            }
        }
    }

    enum SectionOrder: String, Codable, CaseIterable, Sendable {
        case alphabetical, largestFirst, recentlyAdded
    }

    /// Show the library grouped into sections (off = the original flat library).
    var groupIntoSections: Bool = true
    /// New words get a section and tags automatically when they are saved.
    var autoOrganizeNewWords: Bool = true
    var granularity: Granularity = .balanced
    var sectionOrder: SectionOrder = .largestFirst
    /// Upper bound on tags per word (1...6).
    var maxTagsPerWord: Int = 4
    /// Optional free-text steer, e.g. "group by topic, not part of speech".
    var customInstructions: String = ""
    /// Show tag chips under words in the list layout.
    var showTagsInList: Bool = true

    static let `default` = OrganizerSettings()

    init() {}

    /// Tolerant: missing keys (older saved settings) fall back to defaults instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OrganizerSettings()
        groupIntoSections = try c.decodeIfPresent(Bool.self, forKey: .groupIntoSections) ?? d.groupIntoSections
        autoOrganizeNewWords = try c.decodeIfPresent(Bool.self, forKey: .autoOrganizeNewWords) ?? d.autoOrganizeNewWords
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? d.granularity
        sectionOrder = try c.decodeIfPresent(SectionOrder.self, forKey: .sectionOrder) ?? d.sectionOrder
        maxTagsPerWord = min(6, max(1, try c.decodeIfPresent(Int.self, forKey: .maxTagsPerWord) ?? d.maxTagsPerWord))
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? d.customInstructions
        showTagsInList = try c.decodeIfPresent(Bool.self, forKey: .showTagsInList) ?? d.showTagsInList
    }
}
