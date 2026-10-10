import Foundation

/// Solves a typed problem. The live one is Wolfram|Alpha; tests and UI tests use doubles.
protocol MathSolver: Sendable {
    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError>
    /// The same pod with its step-by-step part (costs one more call). `stepsInput` is `SolvePod.stepsInput`.
    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError>
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
