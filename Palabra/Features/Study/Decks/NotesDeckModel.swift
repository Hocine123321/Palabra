import Foundation
import Observation

/// Drives "New deck from notes": notes -> AI -> editable preview -> save.
/// Nothing is persisted until `save()`.
@MainActor
@Observable
final class NotesDeckModel {
    enum Phase: Equatable {
        case input
        case generating
        case preview
        case failed(AIError)
    }

    var notes = ""
    var title = ""
    var drafts: [CardDraft] = []
    private(set) var phase: Phase = .input

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var canGenerate: Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= CardGeneratorLimits.minNotesLength
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.contains { !$0.front.isEmpty && !$0.back.isEmpty }
    }

    func generate() async {
        phase = .generating
        await run(repairedModel: false)
    }

    func backToInput() { phase = .input }

    func deleteDrafts(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
    }

    /// Saves the previewed deck. Returns the new deck's id, or `nil` if there is nothing valid to save.
    func save() -> UUID? {
        guard canSave else { return nil }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return environment.cards.createDeck(name: name, drafts: drafts, now: Date()).id
    }

    private func run(repairedModel: Bool) async {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            phase = .failed(.missingAPIKey)
            return
        }
        guard let model = environment.selectedModel else {
            if environment.selectedModelID != nil, !repairedModel, await environment.repairMissingModel() != nil {
                await run(repairedModel: true)
                return
            }
            phase = .failed(environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? ""))
            return
        }
        switch await CardGenerator(ai: environment.ai).generate(notes: notes, apiKey: apiKey, model: model) {
        case .success(let deck):
            title = deck.title
            drafts = deck.cards
            phase = .preview
        case .failure(let error):
            phase = .failed(error)
            if case .modelUnavailable = error, !repairedModel, await environment.repairMissingModel() != nil {
                await run(repairedModel: true)
            }
        }
    }
}
