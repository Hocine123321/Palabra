import Foundation
import Observation
import SwiftData

/// Everything the Solve tab needs, in one place: the solver, the photo reader, the saved answers and the optional Wolfram|Alpha App ID.
/// Lives on `AppEnvironment` (`environment.solve`).
@MainActor
@Observable
final class SolveTool {
    @ObservationIgnored let solver: MathSolver
    @ObservationIgnored let recognizer: TextRecognizer
    @ObservationIgnored let history: SolveRepository
    @ObservationIgnored private let usage: SolveUsage
    @ObservationIgnored private let keychain: KeychainStore
    /// Set on the live tool: how the Gemini solver reaches the app's AI client, key and model.
    @ObservationIgnored private let geminiLink: GeminiLink?

    private(set) var hasKey: Bool
    /// Calls made this month (a local estimate, see `SolveUsage`).
    private(set) var callsThisMonth: Int

    init(solver: MathSolver, recognizer: TextRecognizer, history: SolveRepository, usage: SolveUsage = SolveUsage(), keychain: KeychainStore = .wolfram(), geminiLink: GeminiLink? = nil, now: Date = Date()) {
        self.solver = solver
        self.geminiLink = geminiLink
        self.recognizer = recognizer
        self.history = history
        self.usage = usage
        self.keychain = keychain
        hasKey = keychain.read() != nil
        callsThisMonth = usage.count(now: now)
    }

    /// The real thing: the on-device math engine, Wolfram|Alpha when an App ID is saved, Gemini for steps and as a
    /// fallback, and on-device text reading. Call `attachAI` once the app environment exists.
    static func live(context: ModelContext) -> SolveTool {
        let link = GeminiLink()
        let solver = CompositeMathSolver(local: LocalMathSolver(), wolfram: WolframSolver(), gemini: GeminiMathSolver(link: link))
        return SolveTool(solver: solver, recognizer: VisionTextRecognizer(), history: SwiftDataSolveRepository(context: context), geminiLink: link)
    }

    /// Lets the Gemini solver use the app's AI client, API key, selected model and language. No-op on test tools.
    func attachAI(_ provider: @escaping GeminiLink.Provider) {
        geminiLink?.attach(provider)
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
