import Foundation
import Observation
import SwiftData

/// Everything the Solve tab needs, in one place: the solver, the photo reader, the saved answers and the App ID.
/// Lives on `AppEnvironment` (`environment.solve`).
@MainActor
@Observable
final class SolveTool {
    @ObservationIgnored let solver: MathSolver
    @ObservationIgnored let recognizer: TextRecognizer
    @ObservationIgnored let history: SolveRepository
    @ObservationIgnored private let usage: SolveUsage
    @ObservationIgnored private let keychain: KeychainStore

    private(set) var hasKey: Bool
    /// Calls made this month (a local estimate, see `SolveUsage`).
    private(set) var callsThisMonth: Int

    init(solver: MathSolver, recognizer: TextRecognizer, history: SolveRepository, usage: SolveUsage = SolveUsage(), keychain: KeychainStore = .wolfram(), now: Date = Date()) {
        self.solver = solver
        self.recognizer = recognizer
        self.history = history
        self.usage = usage
        self.keychain = keychain
        hasKey = keychain.read() != nil
        callsThisMonth = usage.count(now: now)
    }

    /// The real thing: Wolfram|Alpha and on-device text reading.
    static func live(context: ModelContext) -> SolveTool {
        SolveTool(solver: WolframSolver(), recognizer: VisionTextRecognizer(), history: SwiftDataSolveRepository(context: context))
    }

    /// Private store and canned answers: the default for tests and previews that don't care about Solve.
    static func inMemory() -> SolveTool {
        SolveTool(
            solver: StubMathSolver(),
            recognizer: StubTextRecognizer(),
            history: SwiftDataSolveRepository.inMemory(),
            usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-\(UUID().uuidString)") ?? .standard),
            keychain: KeychainStore(account: "wolfram-app-id-inmemory")
        )
    }

    var appID: String? { keychain.read() }

    @discardableResult
    func saveAppID(_ value: String) -> Bool {
        let ok = keychain.save(value)
        hasKey = keychain.read() != nil
        return ok
    }

    func removeAppID() {
        keychain.delete()
        hasKey = false
    }

    func recordCall(now: Date = Date()) {
        usage.record(now: now)
        callsThisMonth = usage.count(now: now)
    }
}
