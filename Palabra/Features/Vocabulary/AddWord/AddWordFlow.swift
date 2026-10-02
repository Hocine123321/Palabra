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
        switch await environment.ai.generateWord(inputWord, apiKey: apiKey, model: model, language: environment.aiLanguage) {
        case .success(let content):
            interpretedDifferently = WordKey.identity(content.word) != WordKey.identity(inputWord)
            phase = .loaded(content)
        case .failure(let error):
            phase = .failed(error)
            // Repair at most once per request, so a second missing model can't loop.
            if case .modelUnavailable = error, !repairedModel, await environment.repairMissingModel() != nil {
                await generate(repairedModel: true)
            }
        }
    }

    /// Writes the loaded content through the repository, then kicks off
    /// pronunciation generation in the background (silently, if configured —
    /// see `AppEnvironment.requestPronunciationIfConfigured`). Returns `nil`
    /// if there is nothing loaded yet to save.
    @discardableResult
    func save() -> Word? {
        guard case .loaded(let content) = phase else { return nil }
        let key = WordKey.identity(content.word)
        let searchKey = WordKey.search(content.word)
        let rawData = (try? JSONEncoder().encode(content)) ?? Data()
        switch mode {
        case .new:
            // Guard a race: another save could have claimed this key while we were generating.
            if let existing = environment.repository.find(key: key) {
                environment.repository.replaceContent(id: existing.id, content: content, rawJSON: rawData)
            } else {
                environment.repository.insert(spanish: content.word, key: key, searchKey: searchKey, content: content, rawJSON: rawData)
            }
        case .regenerate(let existingID, _):
            environment.repository.replaceContent(id: existingID, content: content, rawJSON: rawData)
        }
        // On regenerate the headword may have been corrected, so the new key can differ
        // from the stored one: find the word by id there, by key for a new word.
        let saved: Word?
        if case .regenerate(let existingID, _) = mode {
            saved = environment.repository.allWords().first { $0.id == existingID }
        } else {
            saved = environment.repository.find(key: key)
        }
        if let saved {
            environment.requestPronunciationIfConfigured(for: saved)
            // A regenerated word keeps its existing section and tags.
            if saved.category == nil { environment.requestOrganizationIfConfigured(for: saved) }
        }
        return saved
    }
}
