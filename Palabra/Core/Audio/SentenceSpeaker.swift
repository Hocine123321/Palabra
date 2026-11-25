import AVFoundation
import Observation

/// Reads one Spanish sentence aloud with the phone's own voice: free, offline, instant (the headword's clip, by
/// contrast, is Gemini speech). One instance per screen; tapping the sentence that is playing stops it.
@MainActor
@Observable
final class SentenceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    /// The sentence being spoken, so its button can show "stop".
    private(set) var speaking: String?
    /// The characters being spoken right now (UTF-16 range in `speaking`), so the sentence can light up word by word.
    private(set) var spokenRange: NSRange?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// A stopped utterance reports "cancelled" late; only the current one may clear `speaking`.
    @ObservationIgnored private var currentID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `slow` reads at a learner's pace instead of the normal one.
    func toggle(_ text: String, slow: Bool = false) {
        if speaking == text {
            stop()
            return
        }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.9)
        // Same courtesy as the pronunciation player: never cut off the person's music.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        currentID = ObjectIdentifier(utterance)
        speaking = text
        spokenRange = nil
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentID = nil
        speaking = nil
        spokenRange = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.currentID == id else { return }
            self.spokenRange = characterRange
        }
    }

    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.currentID == id else { return }
            self.currentID = nil
            self.speaking = nil
            self.spokenRange = nil
        }
    }
}
