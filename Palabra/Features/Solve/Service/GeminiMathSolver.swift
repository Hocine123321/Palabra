import Foundation

/// Where the Gemini solver gets its client, key, model and language. Attached by `AppEnvironment` once it exists,
/// because the Solve tool is built before the environment that owns those things.
final class GeminiLink: @unchecked Sendable {
    struct Credentials: Sendable {
        let ai: AIClient
        let apiKey: String
        let model: AIModel
        let language: SupportedLanguage
    }

    typealias Provider = @MainActor @Sendable () -> Credentials?

    private let lock = NSLock()
    private var provider: Provider?

    func attach(_ provider: @escaping Provider) {
        lock.lock()
        defer { lock.unlock() }
        self.provider = provider
    }

    func credentials() async -> Credentials? {
        lock.lock()
        let current = provider
        lock.unlock()
        guard let current else { return nil }
        return await current()
    }
}

/// Solves with Gemini: the fallback for what the on-device engine can't answer, and the writer of step-by-step
/// explanations for answers the engine already verified. Uses the generic `generateJSON` call with a response schema.
struct GeminiMathSolver: MathSolver {
    /// `SolvePod.stepsInput` starts with this when Gemini should write the steps; the rest is the verified answer.
    static let stepsPrefix = "ai:"
    static let maxAnswerLength = 400
    static let maxStepLength = 400
    static let maxSteps = 12
    static let maxQueryLength = MathInputNormalizer.maxLength

    let link: GeminiLink

    init(link: GeminiLink) { self.link = link }

    // MARK: - MathSolver

    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        guard let credentials = await link.credentials() else { return .failure(.missingKey) }
        let prompt = String(query.prefix(Self.maxQueryLength))
        let result = await credentials.ai.generateJSON(
            prompt: "Problem: \(prompt)",
            systemInstruction: Self.solveInstruction(language: credentials.language),
            schema: Self.solveSchema,
            apiKey: credentials.apiKey,
            model: credentials.model,
            temperature: 0
        )
        switch result {
        case .failure(let error): return .failure(Self.solveError(for: error))
        case .success(let text): return Self.parseSolution(text, query: query)
        }
    }

    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        guard stepsInput.hasPrefix(Self.stepsPrefix) else { return .failure(.noSteps) }
        let answer = String(stepsInput.dropFirst(Self.stepsPrefix.count))
        guard let credentials = await link.credentials() else { return .failure(.missingKey) }
        let result = await credentials.ai.generateJSON(
            prompt: "Problem: \(String(query.prefix(Self.maxQueryLength)))\nVerified answer: \(String(answer.prefix(Self.maxAnswerLength)))",
            systemInstruction: Self.stepsInstruction(language: credentials.language),
            schema: Self.stepsSchema,
            apiKey: credentials.apiKey,
            model: credentials.model,
            temperature: 0
        )
        switch result {
        case .failure(let error):
            return .failure(Self.solveError(for: error))
        case .success(let text):
            guard let steps = Self.parseSteps(text), !steps.isEmpty else { return .failure(.noSteps) }
            return .success(Self.pod(id: podID, answer: answer, steps: steps))
        }
    }

    // MARK: - Prompts

    static func solveInstruction(language: SupportedLanguage) -> String {
        """
        You are a careful math solver for a student. Solve the problem exactly, then check the answer by substituting it back.
        Write plain text only: no LaTeX, no markdown. Use ^ for powers, sqrt(), pi, and a/b for fractions.
        Use school conventions: log is base 10, ln is natural, angles are in radians unless the problem says degrees.
        "interpretation" restates the problem in one line. "answer" is the final answer only; give several answers separated by " or ".
        "steps" are 3 to \(maxSteps) short lines, one idea each. \(languageLine(language))
        If the input is not a math problem, or is too ambiguous to solve, set "solvable" to false and leave the other fields empty.
        Never guess: if you cannot reach an answer you trust, set "solvable" to false.
        """
    }

    static func stepsInstruction(language: SupportedLanguage) -> String {
        """
        You are a careful math tutor. The student's problem and its verified answer are given. The answer is correct.
        Write 3 to \(maxSteps) short steps that lead to exactly that answer, one idea per line, in plain text with no LaTeX and no markdown.
        Use ^ for powers, sqrt(), pi, and a/b for fractions. \(languageLine(language))
        """
    }

    private static func languageLine(_ language: SupportedLanguage) -> String {
        language == .arabic
            ? "Write the steps in Arabic, but keep all mathematical notation in plain ASCII as above."
            : "Write the steps in English."
    }

    // MARK: - Schemas

    static let solveSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["solvable", "interpretation", "answer", "steps"],
        "properties": [
            "solvable": ["type": "BOOLEAN"],
            "interpretation": ["type": "STRING"],
            "answer": ["type": "STRING"],
            "steps": ["type": "ARRAY", "items": ["type": "STRING"]],
        ],
        "required": ["solvable", "interpretation", "answer", "steps"],
    ]

    static let stepsSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["steps"],
        "properties": [
            "steps": ["type": "ARRAY", "items": ["type": "STRING"]],
        ],
        "required": ["steps"],
    ]

    // MARK: - Parsing

    private struct Solution: Decodable {
        let solvable: Bool
        let interpretation: String?
        let answer: String?
        let steps: [String]?
    }

    private struct StepsPayload: Decodable {
        let steps: [String]
    }

    static func parseSolution(_ text: String, query: String) -> Result<SolveResult, SolveError> {
        guard let data = text.data(using: .utf8), let solution = try? JSONDecoder().decode(Solution.self, from: data) else {
            return .failure(.malformed)
        }
        let answer = cap(solution.answer ?? "", maxAnswerLength)
        guard solution.solvable, !answer.isEmpty else { return .failure(.noResult(suggestions: [])) }
        let steps = cleanSteps(solution.steps ?? [])
        let interpretation = cap(solution.interpretation ?? "", maxQueryLength)
        var pods = [
            SolvePod(id: "Input", title: "Input", subpods: [SolveSubpod(plaintext: interpretation.isEmpty ? query : interpretation)]),
        ]
        pods.append(pod(id: "Result", answer: answer, steps: steps))
        return .success(SolveResult(query: query, interpretation: interpretation.isEmpty ? nil : interpretation, pods: pods, source: .gemini))
    }

    static func parseSteps(_ text: String) -> [String]? {
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(StepsPayload.self, from: data) else { return nil }
        return cleanSteps(payload.steps)
    }

    /// The answer pod, with the steps as a numbered second part when there are any.
    static func pod(id: String, answer: String, steps: [String]) -> SolvePod {
        var subpods = [SolveSubpod(plaintext: answer)]
        if !steps.isEmpty {
            let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            subpods.append(SolveSubpod(title: "Steps", plaintext: numbered))
        }
        return SolvePod(id: id, title: "Result", primary: true, subpods: subpods, hasSteps: !steps.isEmpty)
    }

    private static func cleanSteps(_ raw: [String]) -> [String] {
        let cleaned = raw
            .map { cap($0, maxStepLength) }
            // The model sometimes numbers its own lines; we number them ourselves.
            .map { $0.replacingOccurrences(of: "^\\s*(?:step\\s*)?[0-9]{1,2}\\s*[.):-]\\s*", with: "", options: [.regularExpression, .caseInsensitive]) }
            .filter { !$0.isEmpty }
        return Array(cleaned.prefix(maxSteps))
    }

    private static func cap(_ value: String, _ limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// Gemini's failures in the Solve tab's terms.
    static func solveError(for error: AIError) -> SolveError {
        switch error {
        case .offline, .timeout, .serverError, .unknown: return .network
        case .rateLimited, .quotaExhausted: return .rateLimited
        case .missingAPIKey, .noModelSelected, .modelUnavailable, .invalidAPIKey, .permissionDenied, .emptyCatalogue: return .missingKey
        case .blocked: return .noResult(suggestions: [])
        case .truncated, .malformedResponse, .validationFailed: return .malformed
        }
    }
}

/// Tries the sources in order: the on-device engine (instant, offline, exact), then Wolfram|Alpha when the person
/// has saved an App ID, then Gemini. Steps come from whoever the answer's `stepsInput` points at.
struct CompositeMathSolver: MathSolver {
    let local: MathSolver
    /// Optional second opinion; only asked when `appID` is not empty.
    let wolfram: MathSolver?
    let gemini: MathSolver

    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        if case .success(let result) = await local.solve(query: query, appID: appID) { return .success(result) }

        var wolframFailure: SolveError?
        if let wolfram, !appID.isEmpty {
            switch await wolfram.solve(query: query, appID: appID) {
            case .success(let result): return .success(result)
            case .failure(let error): wolframFailure = error
            }
        }

        switch await gemini.solve(query: query, appID: appID) {
        case .success(let result):
            return .success(result)
        case .failure(let error):
            // When Gemini can't help either, the more specific reason wins: Wolfram's "did you mean ..." is useful.
            if let wolframFailure {
                switch (error, wolframFailure) {
                case (.missingKey, _), (.noResult, .noResult): return .failure(wolframFailure)
                default: break
                }
            }
            return .failure(error)
        }
    }

    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        if stepsInput.hasPrefix(GeminiMathSolver.stepsPrefix) {
            return await gemini.steps(query: query, podID: podID, stepsInput: stepsInput, appID: appID)
        }
        guard let wolfram, !appID.isEmpty else { return .failure(.noSteps) }
        return await wolfram.steps(query: query, podID: podID, stepsInput: stepsInput, appID: appID)
    }
}
