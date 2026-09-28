import Foundation

/// Keeps only the text-to-speech models from Google's `models.list` — the
/// mirror image of `ModelFilter`, which excludes them. Every Gemini TTS
/// model name contains "tts" (`gemini-2.5-flash-tts`,
/// `gemini-3.1-flash-tts-preview`, `gemini-3.8-flash-lite-tts`, etc.), so the
/// same substring check used to exclude them there is used to select them
/// here. Sorted newest-first, same as `ModelFilter`.
enum TTSModelFilter {
    static func apply(_ models: [AIModel]) -> [AIModel] {
        models
            .filter { $0.id.localizedCaseInsensitiveContains("tts") }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedDescending }
    }
}
