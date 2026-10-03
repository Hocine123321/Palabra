import Foundation
import Observation

/// Drives one Add-word attempt: calls the AI, validates and shows the
/// result, and — on Save — writes through the repository. A fresh instance
/// is created per attempt; `-UITestStub`'s `fallo` word exercises the
/// failure path end to end.
@MainActor
@Observable
final class AddWordFlow: Identifiable {
    enum Phase: Equatable {
        case loading
        case loaded(WordContent)
        case failed(AIError)
        /// Offline: queued for `WordQueueProcessor` to generate once the
        /// connection returns, and already saved to that queue — not lost
        /// if the person just dismisses the sheet.
        case queued
    }

    enum Mode: Equatable {
        case new
        case regenerate(existingID: UUID, existingCreatedAt: Date)
    }

    let id = UUID()
    let inputWord: String
    let mode: Mode
    private(set) var phase: Phase = .loading
    private(set) var interpretedDifferently = false

    private let environment: AppEnvironment

    init(inputWord: String, mode: Mode, environment: AppEnvironment) {
        self.inputWord = inputWord
        self.mode = mode
        self.environment = environment
    }

    func start() async {
        await generate()
    }

    func retry() async {
        phase = .loading
        await generate()
    }

    private func generate(repairedModel: Bool = false) async {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            phase = .failed(.missingAPIKey)
            return
        }
        guard let model = environment.selectedModel else {
            // A saved selection that no longer exists in the catalogue: try to repair it once.
            if environment.selectedModelID != nil, !repairedModel, await environment.repairMissingModel() != nil {
                await generate(repairedModel: true)
                return
            }
            phase = .failed(environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? ""))
            return
        }
        // Already offline: don't even try the request (and the resilient
        // client's own ~45s wait-then-ask) — queue it right away.
        guard environment.connectivity.isConnected else {
            enqueueOffline()
            return
        }
        switch await environment.ai.generateWord(inputWord, apiKey: apiKey, model: model, language: environment.aiLanguage) {
        case .success(let content):
            interpretedDifferently = WordKey.identity(content.word) != WordKey.identity(inputWord)
            phase = .loaded(content)
        case .failure(let error):
            // The connection dropped mid-request and stayed down long enough that the
            // resilient client gave up (or the person chose "Stop" on its dialog):
            // queue instead of a dead-end error, same as the upfront check above.
            if error == .offline {
                enqueueOffline()
                return
            }
            phase = .failed(error)
            // Repair at most once per request, so a second missing model can't loop.
            if case .modelUnavailable = error, !repairedModel, await environment.repairMissingModel() != nil {
                await generate(repairedModel: true)
            }
        }
    }

    private func enqueueOffline() {
        environment.wordQueue.enqueue(inputWord: inputWord, mode: mode, language: environment.aiLanguage)
        environment.queueProcessor.drain(environment: environment)
        phase = .queued
    }

    /// Writes the loaded content through the repository, then kicks off
    /// pronunciation generation in the background (silently, if configured —
    /// see `AppEnvironment.requestPronunciationIfConfigured`). Returns `nil`
    /// if there is nothing loaded yet to save.
    @discardableResult
    func save() -> Word? {
        guard case .loaded(let content) = phase else { return nil }
        return WordWriter.commit(content: content, mode: mode, environment: environment)
    }
}
