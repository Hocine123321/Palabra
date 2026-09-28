import Foundation

/// Keeps the models this app can actually use: drops non-text modalities,
/// sorted newest-first (numeric-aware, so "2.5" sorts above "1.5").
enum ModelFilter {
    private static let excludedSubstrings = ["tts", "image", "audio"]

    static func apply(_ models: [AIModel]) -> [AIModel] {
        models
            .filter { model in !excludedSubstrings.contains { model.id.localizedCaseInsensitiveContains($0) } }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedDescending }
    }
}
