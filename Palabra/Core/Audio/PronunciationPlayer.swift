import AVFoundation
import Observation

/// Thin `AVAudioPlayer` wrapper for one pronunciation clip. One instance per
/// `PronunciationButton`. Uses `.mixWithOthers` so hearing a word doesn't
/// interrupt any music the person has playing.
@MainActor
@Observable
final class PronunciationPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(data: Data) {
        if isPlaying {
            stop()
        } else {
            play(data: data)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func play(data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = self
            player = newPlayer
            isPlaying = newPlayer.play()
        } catch {
            player = nil
            isPlaying = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.isPlaying = false
        }
    }
}
