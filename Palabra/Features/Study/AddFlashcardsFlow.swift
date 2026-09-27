import Foundation
import Observation

/// Drives one "generate flashcards from notes" attempt: calls the AI,
/// lets the learner pick which drafts to keep, and writes the chosen ones
/// through the repository. Mirrors `AddWordFlow`'s shape.
@MainActor
@Observable
final class AddFlashcardsFlow {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded([FlashcardDraft])
        case failed(AIError)
    }

    private(set) var phase: Phase = .idle
    var selected: Set<Int> = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func generate(subject: String, notes: String) async {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else { return }
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            phase = .failed(.missingAPIKey)
            return
        }
        guard let model = environment.selectedModel else {
            phase = .failed(environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? ""))
            return
        }
        phase = .loading
        switch await environment.ai.generateFlashcards(from: trimmedNotes, subject: subject, apiKey: apiKey, model: model, language: environment.aiLanguage) {
        case .success(let drafts):
            selected = Set(drafts.indices)
            phase = .loaded(drafts)
        case .failure(let error):
            phase = .failed(error)
        }
    }

    /// Saves the currently-selected drafts through the repository.
    /// Returns how many cards were saved.
    @discardableResult
    func save(subject: String) -> Int {
        guard case .loaded(let drafts) = phase else { return 0 }
        let subjectLabel = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSubject = subjectLabel.isEmpty ? "General" : subjectLabel
        var saved = 0
        for index in drafts.indices where selected.contains(index) {
            let draft = drafts[index]
            environment.flashcardRepository.insert(subject: finalSubject, front: draft.front, back: draft.back, hint: draft.hint)
            saved += 1
        }
        return saved
    }
}
