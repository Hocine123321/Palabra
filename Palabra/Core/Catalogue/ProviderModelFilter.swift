import Foundation

/// The model list of OpenRouter and Groq. The client has already dropped what cannot answer text (speech, embeddings,
/// guard models), so this only orders it: by name, so the list is stable and easy to scan.
enum ProviderModelFilter {
    static func apply(_ models: [AIModel]) -> [AIModel] {
        var seen = Set<String>()
        return models
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Names to look for, best first: a strong, fast, widely available model on each provider.
    static let preferred = [
        "llama-3.3-70b-versatile", "gpt-oss-120b", "gemini-2.5-flash", "gemini-flash", "gpt-4o-mini",
        "llama-3.3-70b", "claude-3.5-haiku", "llama-3.1-70b", "llama-3.1-8b-instant", "qwen"
    ]

    /// The first preferred model that is listed (a paid one before a free one, since free ones are tightly limited),
    /// else the first model of the list.
    static func pick(from models: [AIModel]) -> AIModel? {
        for name in preferred {
            let matches = models.filter { $0.id.localizedCaseInsensitiveContains(name) }
            if let paid = matches.first(where: { !$0.id.hasSuffix(":free") }) { return paid }
            if let any = matches.first { return any }
        }
        return models.first
    }
}
