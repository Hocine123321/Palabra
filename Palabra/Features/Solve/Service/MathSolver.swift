import Foundation

/// Solves a typed problem. The live one tries the device, then Wolfram|Alpha (if an App ID is saved), then Gemini; tests and UI tests use doubles.
protocol MathSolver: Sendable {
    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError>
    /// The same pod with its step-by-step part (costs one more call). `stepsInput` is `SolvePod.stepsInput`.
    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError>
    /// Solves straight from a photo: Gemini reads and solves in one step, so nothing is lost in a text copy.
    func solvePhoto(imageData: Data) async -> Result<SolveResult, SolveError>
}

extension MathSolver {
    /// Solvers that can't look at a photo say Gemini is needed.
    func solvePhoto(imageData: Data) async -> Result<SolveResult, SolveError> { .failure(.missingKey) }
}

/// Canned answers for UI tests (`-UITestStub`): no network, no key.
struct StubMathSolver: MathSolver {
    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        if query.contains("fallo") { return .failure(.rateLimited) }
        if query.contains("zzz") { return .failure(.noResult(suggestions: ["x^2 - 4 = 0"])) }
        let input = SolvePod(id: "Input", title: "Input", subpods: [SolveSubpod(plaintext: query)])
        let result = SolvePod(
            id: "Result", title: "Result", primary: true,
            subpods: [SolveSubpod(plaintext: "x = -2 or x = 2")],
            stepsInput: "Result__Step-by-step solution"
        )
        let plot = SolvePod(id: "Plot", title: "Plot", subpods: [SolveSubpod(plaintext: "parabola")])
        return .success(SolveResult(query: query, interpretation: query, pods: [input, result, plot]))
    }

    func solvePhoto(imageData: Data) async -> Result<SolveResult, SolveError> {
        let problem = "3 \u{00D7} 4 + x\u{00B2} = 16"
        let input = SolvePod(id: "Input", title: "Input", subpods: [SolveSubpod(plaintext: problem)])
        let result = SolvePod(id: "Result", title: "Result", primary: true, subpods: [SolveSubpod(plaintext: "x = -2 or x = 2")])
        return .success(SolveResult(query: problem, interpretation: problem, pods: [input, result], source: .gemini))
    }

    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        .success(SolvePod(
            id: podID, title: "Result", primary: true,
            subpods: [
                SolveSubpod(plaintext: "x = -2 or x = 2"),
                SolveSubpod(title: "Possible intermediate steps", plaintext: "x^2 = 4, so x = ±2"),
            ],
            hasSteps: true
        ))
    }
}
