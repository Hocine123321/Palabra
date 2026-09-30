import Foundation
import Observation

/// Runs "Re-organize library": sends the words to the AI in batches, then
/// applies the sections and tags it returns. Holds only session state
/// (progress / result); the outcome itself is stored on each `Word`.
///
/// Design notes:
/// - Batches keep big libraries inside the model's output limit. The section
///   names discovered so far are passed to later batches so they reuse them.
/// - Nothing is written until every batch has succeeded, so a failure
///   half-way leaves the library exactly as it was.
/// - Words the AI skipped or mangled fall back to the "Other" section rather than vanishing.
@MainActor
@Observable
final class LibraryOrganizer {
    enum Phase: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(organized: Int, sections: Int)
        case failed(AIError)
    }

    enum Scope: Equatable {
        /// Re-place every word from scratch.
        case all
        /// Only words that have no section yet.
        case unorganizedOnly
    }

    static let batchSize = 40

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func dismissResult() {
        if !isRunning { phase = .idle }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func start(scope: Scope, environment: AppEnvironment) {
        guard !isRunning else { return }
        phase = .running(done: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(scope: scope, environment: environment)
        }
    }

    private func run(scope: Scope, environment: AppEnvironment) async {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else { phase = .failed(.missingAPIKey); return }
        guard let model = environment.selectedModel else {
            phase = .failed(environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? ""))
            return
        }

        let all = environment.repository.allWords()
        let targets = scope == .all ? all : all.filter { $0.category == nil }
        guard !targets.isEmpty else { phase = .finished(organized: 0, sections: Set(all.compactMap(\.category)).count); return }

        let settings = environment.organizerSettings
        var known: [String] = scope == .all ? [] : Array(Set(all.compactMap(\.category))).sorted()
        var placements: [UUID: WordPlacement] = [:]
        let batches = stride(from: 0, to: targets.count, by: Self.batchSize).map { Array(targets[$0..<min($0 + Self.batchSize, targets.count)]) }
        phase = .running(done: 0, total: targets.count)

        for batch in batches {
            if Task.isCancelled { return }
            let inputs = batch.map { OrganizerWordInput(word: $0.spanish, translation: $0.translation, partOfSpeech: $0.partOfSpeech) }
            switch await environment.ai.organizeWords(inputs, existingCategories: known, settings: settings, apiKey: apiKey, model: model, language: environment.aiLanguage) {
            case .failure(let error):
                phase = .failed(error)
                return
            case .success(let result):
                let applied = Self.place(batch: batch, result: result, known: known, maxTags: settings.maxTagsPerWord)
                for (id, placement) in applied {
                    placements[id] = placement
                    if !known.contains(placement.category) { known.append(placement.category) }
                }
            }
            phase = .running(done: placements.count, total: targets.count)
        }

        if Task.isCancelled { return }
        if scope == .all { environment.repository.clearAllPlacements() }
        environment.repository.updatePlacements(placements)
        let sections = Set(environment.repository.allWords().compactMap(\.category)).count
        phase = .finished(organized: placements.count, sections: sections)
    }

    /// Pure: maps an AI batch result onto the batch's words. Matching is by
    /// normalized headword; anything the AI missed lands in the fallback section.
    static func place(batch: [Word], result: OrganizerBatchResult, known: [String], maxTags: Int) -> [UUID: WordPlacement] {
        var byWord: [String: OrganizerBatchResult.Entry] = [:]
        for entry in result.entries { byWord[WordKey.identity(entry.word)] = entry }
        var knownNames = known
        var out: [UUID: WordPlacement] = [:]
        for word in batch {
            let entry = byWord[WordKey.identity(word.spanish)]
            var placement = LibraryTaxonomy.clean(WordPlacement(category: entry?.category ?? "", tags: entry?.tags ?? []))
            placement.category = LibraryTaxonomy.canonicalCategory(placement.category, known: knownNames)
            placement.tags = Array(placement.tags.prefix(maxTags))
            if !knownNames.contains(placement.category) { knownNames.append(placement.category) }
            out[word.id] = placement
        }
        return out
    }
}
