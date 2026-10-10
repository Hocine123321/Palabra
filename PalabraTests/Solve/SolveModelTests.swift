import XCTest
@testable import Palabra

@MainActor
final class SolveModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_644_400) // 2026-10-10
    private let account = "wolfram-app-id-tests-\(UUID().uuidString)"
    private var keychain: KeychainStore!
    private var solver: MockMathSolver!
    private var tool: SolveTool!

    override func setUp() {
        keychain = KeychainStore(account: account)
        solver = MockMathSolver()
        makeTool(recognizer: MockTextRecognizer(result: .success("x² − 4 = 0")))
    }

    override func tearDown() {
        keychain.delete()
    }

    private func makeTool(recognizer: TextRecognizer) {
        tool = SolveTool(
            solver: solver,
            recognizer: recognizer,
            history: SwiftDataSolveRepository.inMemory(),
            usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-tests-\(UUID().uuidString)")!),
            keychain: keychain,
            now: now
        )
    }

    private func model() -> SolveModel { SolveModel(tool: tool, now: { self.now }) }

    // MARK: Solving

    func testSolveSavesResultAndCountsOneCall() async {
        tool.saveAppID("abc")
        solver.solveResults = [.success(.sample())]
        let model = model()
        model.input = "x^2 - 4 = 0"
        let id = await model.solve()
        XCTAssertNotNil(id)
        XCTAssertNil(model.error)
        XCTAssertEqual(tool.callsThisMonth, 1)
        XCTAssertEqual(solver.solveCalls.count, 1)
        XCTAssertEqual(solver.solveCalls.first?.appID, "abc")
        XCTAssertEqual(tool.history.entry(id: id!)?.result, .sample())
    }

    func testRepeatQuestionIsAnsweredFromTheSavedResultWithoutACall() async {
        tool.saveAppID("abc")
        solver.solveResults = [.success(.sample())]
        let model = model()
        model.input = "x^2 - 4 = 0"
        let first = await model.solve()
        model.input = "X^2-4 = 0" // same problem, different spacing and case
        let second = await model.solve()
        XCTAssertEqual(first, second)
        XCTAssertEqual(solver.solveCalls.count, 1, "no second call")
        XCTAssertEqual(tool.callsThisMonth, 1)
    }

    func testCachedAnswerStillWorksWithoutAKey() async {
        tool.saveAppID("abc")
        solver.solveResults = [.success(.sample())]
        let model = model()
        model.input = "x^2 - 4 = 0"
        _ = await model.solve()
        tool.removeAppID()
        let again = await model.solve()
        XCTAssertNotNil(again)
        XCTAssertNil(model.error)
    }

    func testMissingKeyMakesNoCall() async {
        let model = model()
        model.input = "x^2 - 4 = 0"
        let id = await model.solve()
        XCTAssertNil(id)
        XCTAssertEqual(model.error, .missingKey)
        XCTAssertTrue(solver.solveCalls.isEmpty)
        XCTAssertEqual(tool.callsThisMonth, 0)
    }

    func testEmptyInputIsAnError() async {
        tool.saveAppID("abc")
        let model = model()
        model.input = "  "
        let id = await model.solve()
        XCTAssertNil(id)
        XCTAssertEqual(model.error, .emptyInput)
        XCTAssertTrue(solver.solveCalls.isEmpty)
    }

    func testNoResultCountsACallAndKeepsSuggestions() async {
        tool.saveAppID("abc")
        solver.solveResults = [.failure(.noResult(suggestions: ["x^2 - 4 = 0"]))]
        let model = model()
        model.input = "x2 -4 0"
        let id = await model.solve()
        XCTAssertNil(id)
        XCTAssertEqual(model.error, .noResult(suggestions: ["x^2 - 4 = 0"]))
        XCTAssertEqual(tool.callsThisMonth, 1)
    }

    func testNetworkAndKeyFailuresAreNotCounted() async {
        tool.saveAppID("abc")
        solver.solveResults = [.failure(.network), .failure(.invalidKey), .failure(.rateLimited)]
        let model = model()
        model.input = "2+2"
        for expected in [SolveError.network, .invalidKey, .rateLimited] {
            let id = await model.solve()
            XCTAssertNil(id)
            XCTAssertEqual(model.error, expected)
        }
        XCTAssertEqual(tool.callsThisMonth, 0)
    }

    func testFailedProblemIsNotSaved() async {
        tool.saveAppID("abc")
        solver.solveResults = [.failure(.network)]
        let model = model()
        model.input = "2+2"
        _ = await model.solve()
        XCTAssertTrue(tool.history.entries(limit: 10).isEmpty)
    }

    func testSolveSendsTheCleanedProblem() async {
        tool.saveAppID("abc")
        solver.solveResults = [.success(.sample(query: "3*4+x^2"))]
        let model = model()
        model.input = "1. 3 × 4 + x²"
        _ = await model.solve()
        XCTAssertEqual(solver.solveCalls.first?.query, "3 * 4 + x^2")
    }

    // MARK: Photos

    func testRecognizedPhotoFillsTheCleanedInput() async {
        let model = model()
        await model.recognize(imageData: Data([1]))
        XCTAssertEqual(model.input, "x^2 - 4 = 0")
        XCTAssertNil(model.photoMessage)
        XCTAssertEqual(model.phase, .idle)
    }

    func testUnreadablePhotoSetsAMessageAndKeepsTheInput() async {
        makeTool(recognizer: MockTextRecognizer(result: .failure(.unreadable)))
        let model = model()
        model.input = "2+2"
        await model.recognize(imageData: Data([1]))
        XCTAssertEqual(model.input, "2+2")
        XCTAssertEqual(model.photoMessage, RecognitionError.unreadable.userMessage)
    }

    func testPhotoWithOnlyJunkSaysNothingFound() async {
        makeTool(recognizer: MockTextRecognizer(result: .success("   ")))
        let model = model()
        await model.recognize(imageData: Data([1]))
        XCTAssertEqual(model.photoMessage, RecognitionError.nothingFound.userMessage)
        XCTAssertTrue(model.input.isEmpty)
    }
}

@MainActor
final class SolveResultModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_644_400)
    private let account = "wolfram-app-id-tests-\(UUID().uuidString)"
    private var keychain: KeychainStore!
    private var solver: MockMathSolver!
    private var tool: SolveTool!
    private var entryID: UUID!

    override func setUp() {
        keychain = KeychainStore(account: account)
        solver = MockMathSolver()
        tool = SolveTool(
            solver: solver,
            recognizer: MockTextRecognizer(result: .success("")),
            history: SwiftDataSolveRepository.inMemory(),
            usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-tests-\(UUID().uuidString)")!),
            keychain: keychain,
            now: now
        )
        tool.saveAppID("abc")
        entryID = tool.history.save(query: "x^2-4=0", key: "x^2-4=0", result: .sample(), now: now).id
    }

    override func tearDown() {
        keychain.delete()
    }

    private func model() -> SolveResultModel { SolveResultModel(tool: tool, entryID: entryID, now: { self.now }) }

    private func stepsPod() -> SolvePod {
        SolvePod(id: "Result", title: "Result", primary: true, subpods: [
            SolveSubpod(plaintext: "x = -2 or x = 2"),
            SolveSubpod(title: "Possible intermediate steps", plaintext: "x^2 = 4, so x = ±2"),
        ], hasSteps: true)
    }

    func testLoadsTheSavedResult() {
        XCTAssertEqual(model().result, .sample())
    }

    func testMissingEntryHasNoResult() {
        XCTAssertNil(SolveResultModel(tool: tool, entryID: UUID()).result)
    }

    func testStepsReplaceThePodSaveItAndCountOneCall() async {
        solver.stepsResults = [.success(stepsPod())]
        let model = model()
        await model.loadSteps(podID: "Result")
        XCTAssertNil(model.stepsError)
        XCTAssertEqual(solver.stepsCalls.count, 1)
        XCTAssertEqual(solver.stepsCalls.first?.stepsInput, "Result__Step-by-step solution")
        XCTAssertEqual(tool.callsThisMonth, 1)
        let pod = model.result?.pods.first { $0.id == "Result" }
        XCTAssertEqual(pod?.hasSteps, true)
        XCTAssertNil(pod?.stepsInput)
        // Saved, so reopening shows the steps without a call.
        XCTAssertEqual(tool.history.entry(id: entryID)?.result, model.result)
    }

    func testNoStepsClearsTheOfferAndSetsAnError() async {
        solver.stepsResults = [.failure(.noSteps)]
        let model = model()
        await model.loadSteps(podID: "Result")
        XCTAssertEqual(model.stepsError, .noSteps)
        XCTAssertNil(model.result?.pods.first { $0.id == "Result" }?.stepsInput)
        XCTAssertEqual(tool.callsThisMonth, 1)
        // The offer is gone, so a second tap does nothing.
        await model.loadSteps(podID: "Result")
        XCTAssertEqual(solver.stepsCalls.count, 1)
    }

    func testNetworkFailureKeepsTheOfferAndCostsNothing() async {
        solver.stepsResults = [.failure(.network)]
        let model = model()
        await model.loadSteps(podID: "Result")
        XCTAssertEqual(model.stepsError, .network)
        XCTAssertNotNil(model.result?.pods.first { $0.id == "Result" }?.stepsInput)
        XCTAssertEqual(tool.callsThisMonth, 0)
    }

    func testPodWithoutAnOfferMakesNoCall() async {
        let model = model()
        await model.loadSteps(podID: "Plot")
        XCTAssertTrue(solver.stepsCalls.isEmpty)
    }

    func testStepsWithoutAKeyReportsMissingKey() async {
        tool.removeAppID()
        let model = model()
        await model.loadSteps(podID: "Result")
        XCTAssertEqual(model.stepsError, .missingKey)
        XCTAssertTrue(solver.stepsCalls.isEmpty)
    }
}

@MainActor
final class SolveToolTests: XCTestCase {
    func testAppIDRoundTripAndTrim() {
        let keychain = KeychainStore(account: "wolfram-app-id-tests-\(UUID().uuidString)")
        defer { keychain.delete() }
        let tool = SolveTool(solver: MockMathSolver(), recognizer: MockTextRecognizer(result: .success("")), history: SwiftDataSolveRepository.inMemory(),
                             usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-tests-\(UUID().uuidString)")!), keychain: keychain)
        XCTAssertFalse(tool.hasKey)
        tool.saveAppID("  ABC-123 \n")
        XCTAssertTrue(tool.hasKey)
        XCTAssertEqual(tool.appID, "ABC-123")
        tool.removeAppID()
        XCTAssertFalse(tool.hasKey)
        XCTAssertNil(tool.appID)
    }
}
