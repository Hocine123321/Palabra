import Foundation

/// Says a word out loud from a library tile, row or the word screen. One shared instance, so a second
/// tap on another word cuts the first one off instead of overlapping it.
@MainActor
final class WordQuickSpeaker {
    static let shared = WordQuickSpeaker()

    private let sentences = SentenceSpeaker()
    private let clips = PronunciationPlayer()

    /// Plays the word's saved Gemini clip when it has one; otherwise the phone's own Spanish voice
    /// (free, offline, no API call).
    func hear(_ word: Word, environment: AppEnvironment) {
        sentences.stop()
        clips.stop()
        if let audio = environment.repository.pronunciation(id: word.id) {
            clips.toggle(data: audio)
        } else {
            sentences.toggle(word.spanish)
        }
    }

    /// The phone's own voice only. For when Gemini speech isn't set up or just failed.
    func hearWithPhoneVoice(_ text: String) {
        sentences.stop()
        clips.stop()
        sentences.toggle(text)
    }
}
