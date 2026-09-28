import Foundation
import Observation

/// Tracks per-word pronunciation generation for the current app session and
/// drives `AIClient.synthesizeSpeech`. Deliberately holds only transient
/// state here (loading/failed) — the actual audio lives on
/// `Word.pronunciationAudio` via `WordRepository`, so a word that never
/// finished generating (e.g. the app was killed mid-request) just comes back
/// as `.idle` with no audio next launch, rather than stuck `.loading`
/// forever.
@MainActor
@Observable
final class PronunciationService {
    enum Status: Equatable {
        case idle
        case loading
        case failed(AIError)
    }

    private var statuses: [UUID: Status] = [:]

    func status(for wordID: UUID) -> Status {
        statuses[wordID] ?? .idle
    }

    /// Generates (or regenerates) pronunciation audio for `word` and stores
    /// it via `environment.repository`. Always resolves to either a stored
    /// clip or a `.failed` status the UI can show and retry from — including
    /// "no API key" / "no model selected" — so a manual (re)try always gives
    /// clear feedback. Ignored if a request for this word is already in
    /// flight, so a rapid double-tap can't fire two calls at once.
    func generate(for word: Word, using environment: AppEnvironment) async {
        guard status(for: word.id) != .loading else { return }
        statuses[word.id] = .loading

        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            statuses[word.id] = .failed(.missingAPIKey)
            return
        }
        await environment.ensureTTSModelSelected()
        guard let model = environment.selectedTTSModel else {
            statuses[word.id] = .failed(environment.selectedTTSModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedTTSModelID ?? ""))
            return
        }
        switch await environment.ai.synthesizeSpeech(word.content.word, apiKey: apiKey, model: model) {
        case .success(let audio):
            environment.repository.updatePronunciation(id: word.id, audio: audio)
            statuses[word.id] = .idle
        case .failure(let error):
            statuses[word.id] = .failed(error)
        }
    }
}
