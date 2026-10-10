import Foundation
@testable import Palabra

/// A controllable `MathSolver`: returns queued results and records every call.
final class MockMathSolver: MathSolver, @unchecked Sendable {
    private let lock = NSLock()
    private var _solveCalls: [(query: String, appID: String)] = []
    private var _stepsCalls: [(query: String, podID: String, stepsInput: String)] = []
    var solveResults: [Result<SolveResult, SolveError>] = []
    var stepsResults: [Result<SolvePod, SolveError>] = []

    var solveCalls: [(query: String, appID: String)] { lock.lock(); defer { lock.unlock() }; return _solveCalls }
    var stepsCalls: [(query: String, podID: String, stepsInput: String)] { lock.lock(); defer { lock.unlock() }; return _stepsCalls }

    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        lock.lock(); defer { lock.unlock() }
        _solveCalls.append((query, appID))
        return solveResults.isEmpty ? .failure(.malformed) : solveResults.removeFirst()
    }

    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        lock.lock(); defer { lock.unlock() }
        _stepsCalls.append((query, podID, stepsInput))
        return stepsResults.isEmpty ? .failure(.noSteps) : stepsResults.removeFirst()
    }
}

struct MockTextRecognizer: TextRecognizer {
    var result: Result<String, RecognitionError>
    func recognize(imageData: Data) async -> Result<String, RecognitionError> { result }
}

extension SolveResult {
    /// A small answer with a steps offer on its result pod.
    static func sample(query: String = "x^2-4=0", withStepsOffer: Bool = true) -> SolveResult {
        SolveResult(
            query: query,
            interpretation: query,
            pods: [
                SolvePod(id: "Input", title: "Input", subpods: [SolveSubpod(plaintext: query)]),
                SolvePod(id: "Result", title: "Result", primary: true, subpods: [SolveSubpod(plaintext: "x = -2 or x = 2")], stepsInput: withStepsOffer ? "Result__Step-by-step solution" : nil),
                SolvePod(id: "Plot", title: "Plot", subpods: [SolveSubpod(plaintext: "parabola")]),
            ]
        )
    }
}
