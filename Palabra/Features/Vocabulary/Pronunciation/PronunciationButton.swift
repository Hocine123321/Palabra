import SwiftUI

/// Speaker/play control for a word's Gemini-TTS pronunciation, shown next to
/// the Spanish headword on the word detail screen. Generation itself is
/// normally triggered automatically when the word is first saved (see
/// `AppEnvironment.requestPronunciationIfConfigured`) — this button's tap
/// plays the clip once it's ready, and offers a manual (re)try when it isn't
/// (an imported word with no cached audio, or a previous attempt that
/// failed).
struct PronunciationButton: View {
    let word: Word
    @Environment(AppEnvironment.self) private var environment
    @State private var player = PronunciationPlayer()

    /// Whether a clip is saved (a file check, so the word's row is not loaded with its audio).
    private var hasAudio: Bool { environment.repository.hasPronunciation(id: word.id) }

    private var status: PronunciationService.Status {
        environment.pronunciation.status(for: word.id)
    }

    var body: some View {
        Button(action: handleTap) {
            icon
                .font(.title2)
                .frame(width: 44, height: 44)
                // A flat paper disc: this button sits on the headword's cutout, never on glass.
                .background(Color.white.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.onTint)
        .disabled(status == .loading)
        .accessibilityLabel(pronunciationAccessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .loading:
            ProgressView()
        case .failed:
            Image(systemName: "speaker.slash.circle")
        case .idle:
            if hasAudio {
                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
            } else {
                Image(systemName: "speaker.wave.2.circle")
            }
        }
    }

    private var pronunciationAccessibilityLabel: LocalizedStringKey {
        switch status {
        case .loading:
            return "Generating pronunciation…"
        case .failed:
            return "Pronunciation unavailable. Tap to retry."
        case .idle:
            return hasAudio ? "Play pronunciation" : "Hear pronunciation"
        }
    }

    private func handleTap() {
        if status == .loading { return }
        if case .idle = status, let audio = environment.repository.pronunciation(id: word.id) {
            player.toggle(data: audio)
            return
        }
        Task { await environment.pronunciation.generate(for: word, using: environment) }
    }
}

/// One-line reason shown on the word detail screen when the last
/// pronunciation attempt failed, so the speaker icon isn't a silent dead end.
/// Renders nothing in every other state. Pronunciation-specific wording
/// replaces the generic text-model messages for the two model-related
/// failures, which would otherwise point people at the wrong Settings row.
struct PronunciationNotice: View {
    let word: Word
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if case .failed(let error) = environment.pronunciation.status(for: word.id) {
            Label(LocalizedStringKey(message(for: error)), systemImage: "speaker.slash")
                .font(.footnote)
                .foregroundStyle(Theme.error)
        }
    }

    private func message(for error: AIError) -> String {
        switch error {
        case .noModelSelected:
            return "Choose a pronunciation model in Settings."
        case .modelUnavailable:
            return "Your pronunciation model is no longer available. Choose another in Settings."
        default:
            return error.userMessage
        }
    }
}
