import AVFoundation
import Observation

/// Reads one Spanish sentence aloud with the phone's own voice: free, offline, instant (the headword's clip, by
/// contrast, is Gemini speech). One instance per screen; tapping the sentence that is playing stops it.
@MainActor
@Observable
final class SentenceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    /// The sentence being spoken, so its button can show "stop".
    private(set) var speaking: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// A stopped utterance reports "cancelled" late; only the current one may clear `speaking`.
    @ObservationIgnored private var currentID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        if speaking == text {
            stop()
            return
        }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        // Same courtesy as the pronunciation player: never cut off the person's music.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        currentID = ObjectIdentifier(utterance)
        speaking = text
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentID = nil
        speaking = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.currentID == id else { return }
            self.currentID = nil
            self.speaking = nil
        }
    }
}
