import Foundation
import Observation

/// The Solve screen's state: the problem text, reading a photo, and solving (saved answer first, then the solver chain).
@MainActor
@Observable
final class SolveModel {
    enum Phase: Equatable { case idle, reading, solving }

    var input = ""
    private(set) var phase: Phase = .idle
    private(set) var error: SolveError?
    /// Why a photo could not be read (a localization key).
    private(set) var photoMessage: String?

    private let tool: SolveTool
    private let now: () -> Date

    init(tool: SolveTool, now: @escaping () -> Date = { Date() }) {
        self.tool = tool
        self.now = now
    }

    var normalizedInput: String { MathInputNormalizer.normalize(input) }
    var canSolve: Bool { phase == .idle && !normalizedInput.isEmpty }

    /// Reads a photo into the problem box (cleaned up, still editable).
    func recognize(imageData: Data) async {
        guard phase == .idle else { return }
        phase = .reading
        photoMessage = nil
        error = nil
        defer { phase = .idle }
        switch await tool.recognizer.recognize(imageData: imageData) {
        case .success(let text):
            let cleaned = MathInputNormalizer.normalize(text)
            if cleaned.isEmpty {
                photoMessage = RecognitionError.nothingFound.userMessage
            } else {
                input = cleaned
            }
        case .failure(let failure):
            photoMessage = failure.userMessage
        }
    }

    /// Solves the problem. Returns the saved entry's id, or nil with `error` set.
    /// A problem asked before is answered from the saved result: no call is spent.
    func solve() async -> UUID? {
        guard phase == .idle else { return nil }
        photoMessage = nil
        let query = normalizedInput
        guard !query.isEmpty else { error = .emptyInput; return nil }
        let key = MathInputNormalizer.key(for: query)
        let moment = now()

        if let cached = tool.history.entry(forKey: key), let result = cached.result {
            error = nil
            return tool.history.save(query: cached.query, key: key, result: result, now: moment).id
        }
        // The App ID is optional: without one the chain is the on-device engine, then Gemini.
        let appID = tool.appID ?? ""

        phase = .solving
        error = nil
        defer { phase = .idle }
        let outcome = await tool.solver.solve(query: query, appID: appID)
        // The person pressed Cancel: no answer saved, no error shown, nothing counted.
        if Task.isCancelled { return nil }
        switch outcome {
        case .success(let result):
            // Only Wolfram|Alpha's answers use its free calls.
            if result.isFromWolfram { tool.recordCall(now: moment) }
            return tool.history.save(query: query, key: key, result: result, now: moment).id
        case .failure(let failure):
            // Wolfram counts a question it could not understand; a dead connection or a refused key costs nothing.
            if case .noResult = failure, !appID.isEmpty { tool.recordCall(now: moment) }
            error = failure
            return nil
        }
    }

    func dismissError() { error = nil }
}

/// The result screen's state: the saved answer, and loading steps on demand.
@MainActor
@Observable
final class SolveResultModel {
    let entryID: UUID
    private(set) var result: SolveResult?
    /// The pod whose steps are loading.
    private(set) var loadingStepsPodID: String?
    private(set) var stepsError: SolveError?

    private let tool: SolveTool
    private let now: () -> Date

    init(tool: SolveTool, entryID: UUID, now: @escaping () -> Date = { Date() }) {
        self.tool = tool
        self.entryID = entryID
        self.now = now
        result = tool.history.entry(id: entryID)?.result
    }

    /// Gets one pod's steps and saves the richer answer: from Gemini (no free call used) or, for a Wolfram|Alpha
    /// answer, from Wolfram|Alpha (one more call).
    func loadSteps(podID: String) async {
        guard loadingStepsPodID == nil, let current = result,
              let pod = current.pods.first(where: { $0.id == podID }), let stepsInput = pod.stepsInput else { return }
        let appID = tool.appID ?? ""
        let usesWolframCall = !pod.stepsAreAIWritten
        loadingStepsPodID = podID
        stepsError = nil
        defer { loadingStepsPodID = nil }
        switch await tool.solver.steps(query: current.query, podID: podID, stepsInput: stepsInput, appID: appID) {
        case .success(let richer):
            if usesWolframCall { tool.recordCall(now: now()) }
            let updated = current.replacing(richer)
            result = updated
            tool.history.update(id: entryID, result: updated, now: now())
        case .failure(let failure):
            if failure == .noSteps {
                if usesWolframCall { tool.recordCall(now: now()) }
                // Remember there is nothing to fetch, so the button does not offer it again.
                var withoutOffer = pod
                withoutOffer.stepsInput = nil
                let updated = current.replacing(withoutOffer)
                result = updated
                tool.history.update(id: entryID, result: updated, now: now())
            }
            stepsError = failure
        }
    }

    func dismissStepsError() { stepsError = nil }
}
