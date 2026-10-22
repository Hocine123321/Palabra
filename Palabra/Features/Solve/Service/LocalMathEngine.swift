import Foundation
import JavaScriptCore

/// The on-device math engine: nerdamer (a computer algebra system, bundled as `nerdamer.bundle.js`) driven by
/// `solver.js` inside JavaScriptCore. No network, no key, no limit. It only answers what it can check; for
/// everything else it says "unsupported" and the caller falls back to Gemini.
final class LocalMathEngine: @unchecked Sendable {
    struct Answer: Equatable, Sendable {
        struct Extra: Equatable, Sendable {
            let title: String
            let text: String
        }
        let kind: String
        let interpretation: String
        let answer: String
        let extras: [Extra]
    }

    enum Outcome: Equatable, Sendable {
        case answer(Answer)
        /// The engine understood the problem but won't vouch for an answer (or could not read it).
        case unsupported
        /// The scripts could not be loaded (a packaging problem); callers treat it like `unsupported`.
        case unavailable
    }

    /// A problem that takes longer than this is given up on.
    static let timeout: TimeInterval = 8

    /// One JavaScript context and the serial queue that owns it. A context is single-threaded, so each lives on its own queue.
    private final class Lane: @unchecked Sendable {
        let queue = DispatchQueue(label: "dev.palabra.math", qos: .userInitiated)
        var context: JSContext?
    }

    /// Resumes a continuation exactly once, from whichever of the answer or the timeout comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?
        init(_ continuation: CheckedContinuation<Outcome, Never>) { self.continuation = continuation }
        @discardableResult
        func resume(_ outcome: Outcome) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard let continuation else { return false }
            self.continuation = nil
            continuation.resume(returning: outcome)
            return true
        }
    }

    private let bundle: Bundle
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var lane = Lane()

    init(bundle: Bundle = Bundle(for: LocalMathEngine.self), timeout: TimeInterval = LocalMathEngine.timeout) {
        self.bundle = bundle
        self.timeout = timeout
    }

    /// Inputs that make the engine spin for minutes (huge factorials, huge exponents). A run cannot be killed once
    /// started, only abandoned, so these are refused up front and left to the Gemini fallback.
    static func isTooHeavy(_ query: String) -> Bool {
        func exceeds(_ pattern: String, _ limit: Double) -> Bool {
            var from = query.startIndex
            while let range = query.range(of: pattern, options: .regularExpression, range: from..<query.endIndex) {
                if let value = Double(query[range].filter(\.isNumber)), value >= limit { return true }
                from = range.upperBound
            }
            return false
        }
        return exceeds("[0-9]+(?=\\s*!)", 500) || exceeds("(?<=\\^)\\s*\\(?\\s*[0-9]+", 1_000)
    }

    func solve(_ query: String) async -> Outcome {
        if Self.isTooHeavy(query) { return .unsupported }
        let current = currentLane()
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            current.queue.async { [bundle] in
                once.resume(Self.run(query, in: current, bundle: bundle))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                // Still running: give up, and move later problems to a fresh context so they don't queue behind this one.
                if once.resume(.unsupported) { self?.replaceLane(ifCurrent: current) }
            }
        }
    }

    private func currentLane() -> Lane {
        lock.lock()
        defer { lock.unlock() }
        return lane
    }

    private func replaceLane(ifCurrent old: Lane) {
        lock.lock()
        defer { lock.unlock() }
        if lane === old { lane = Lane() }
    }

    // MARK: - Running (on the lane's queue)

    private static func run(_ query: String, in lane: Lane, bundle: Bundle) -> Outcome {
        if lane.context == nil { lane.context = makeContext(bundle: bundle) }
        guard let context = lane.context, let function = context.objectForKeyedSubscript("palabraSolve"), function.isObject else {
            return .unavailable
        }
        guard let json = function.call(withArguments: [query])?.toString(), let data = json.data(using: .utf8) else {
            return .unsupported
        }
        return parse(data)
    }

    /// XcodeGen copies resources flat; fall back to the `Math` folder in case they are folder-referenced.
    private static func resource(_ name: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: "js")
            ?? bundle.url(forResource: name, withExtension: "js", subdirectory: "Math")
    }

    private static func makeContext(bundle: Bundle) -> JSContext? {
        guard let context = JSContext(),
              let engineURL = Self.resource("nerdamer.bundle", in: bundle),
              let solverURL = Self.resource("solver", in: bundle),
              let engine = try? String(contentsOf: engineURL, encoding: .utf8),
              let solver = try? String(contentsOf: solverURL, encoding: .utf8) else { return nil }
        context.exceptionHandler = { _, _ in }
        context.evaluateScript(engine)
        context.evaluateScript(solver)
        return context
    }

    private struct Payload: Decodable {
        struct Extra: Decodable {
            let title: String
            let text: String
        }
        let ok: Bool
        let kind: String?
        let interpretation: String?
        let answer: String?
        let extras: [Extra]?
    }

    /// Decodes `palabraSolve`'s JSON. Anything that isn't a clear, non-empty answer is "unsupported".
    static func parse(_ data: Data) -> Outcome {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.ok,
              let answer = payload.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
            return .unsupported
        }
        let extras = (payload.extras ?? []).compactMap { extra -> Answer.Extra? in
            let text = extra.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Answer.Extra(title: extra.title, text: text)
        }
        return .answer(Answer(kind: payload.kind ?? "", interpretation: payload.interpretation ?? "", answer: answer, extras: extras))
    }
}

/// Solves a typed problem with `LocalMathEngine`. Needs no App ID and no network.
struct LocalMathSolver: MathSolver {
    let engine: LocalMathEngine

    init(engine: LocalMathEngine = LocalMathEngine()) { self.engine = engine }

    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        switch await engine.solve(query) {
        case .answer(let answer):
            return .success(Self.result(for: query, answer: answer))
        case .unsupported, .unavailable:
            return .failure(.noResult(suggestions: []))
        }
    }

    /// Steps for an on-device answer are written by Gemini (see `GeminiMathSolver`); the engine has none of its own.
    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        .failure(.noSteps)
    }

    static func result(for query: String, answer: LocalMathEngine.Answer) -> SolveResult {
        var pods = [
            SolvePod(id: "Input", title: "Input", subpods: [SolveSubpod(plaintext: answer.interpretation.isEmpty ? query : answer.interpretation)]),
            SolvePod(
                id: "Result", title: "Result", primary: true,
                subpods: [SolveSubpod(plaintext: answer.answer)],
                stepsInput: GeminiMathSolver.stepsPrefix + answer.answer
            ),
        ]
        for (index, extra) in answer.extras.enumerated() {
            pods.append(SolvePod(id: "Extra\(index)", title: extra.title, subpods: [SolveSubpod(plaintext: extra.text)]))
        }
        return SolveResult(query: query, interpretation: answer.interpretation, pods: pods, source: .onDevice)
    }
}
