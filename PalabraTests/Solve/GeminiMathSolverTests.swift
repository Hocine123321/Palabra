import XCTest
@testable import Palabra

@MainActor
final class GeminiMathSolverTests: XCTestCase {
    private let model = AIModel(id: "models/gemini-test", displayName: "Test", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    private var ai: MockAIClient!
    private var link: GeminiLink!
    private var solver: GeminiMathSolver!

    override func setUp() {
        ai = MockAIClient()
        link = GeminiLink()
        solver = GeminiMathSolver(link: link)
    }

    private func attach(language: SupportedLanguage = .english) {
        let ai = self.ai!, model = self.model
        link.attach { GeminiLink.Credentials(ai: ai, apiKey: "key", model: model, language: language) }
    }

    private let solvedJSON = """
    {"solvable": true, "interpretation": "integral of x e^x", "answer": "e^x (x - 1) + C",
     "steps": ["1. Use integration by parts.", "Let u = x and dv = e^x dx.", "Step 3: Simplify."]}
    """

    // MARK: Solving

    func testSolveSendsTheProblemAndBuildsAnAnswerWithSteps() async throws {
        attach()
        ai.generateJSONResult = .success(solvedJSON)
        let result = await solver.solve(query: "integral of x e^x", appID: "")
        let solved = try XCTUnwrap(result.success)

        // What was actually sent.
        let call = try XCTUnwrap(ai.generateJSONCalls.first)
        XCTAssertEqual(call.prompt, "Problem: integral of x e^x")
        XCTAssertTrue(call.systemInstruction.contains("plain text"))
        XCTAssertTrue(call.systemInstruction.contains("Write the steps in English."))
        XCTAssertEqual((call.schema?["required"] as? [String])?.sorted(), ["answer", "interpretation", "solvable", "steps"])

        XCTAssertEqual(solved.source, .gemini)
        XCTAssertEqual(solved.answerText.components(separatedBy: "\n").first, "e^x (x - 1) + C")
        let steps = try XCTUnwrap(solved.answerPod?.subpods.last)
        XCTAssertEqual(steps.title, "Steps")
        XCTAssertEqual(steps.plaintext, "1. Use integration by parts.\n2. Let u = x and dv = e^x dx.\n3. Simplify.", "the model's own numbering is replaced by ours")
        XCTAssertEqual(solved.answerPod?.hasSteps, true)
        XCTAssertNil(solved.answerPod?.stepsInput)
    }

    func testArabicAsksForArabicStepsButAsciiMath() async {
        attach(language: .arabic)
        ai.generateJSONResult = .success(solvedJSON)
        _ = await solver.solve(query: "x", appID: "")
        XCTAssertTrue(ai.generateJSONCalls.first?.systemInstruction.contains("Write the steps in Arabic") ?? false)
    }

    func testNotSolvableIsNoResult() async {
        attach()
        ai.generateJSONResult = .success("{\"solvable\": false, \"interpretation\": \"\", \"answer\": \"\", \"steps\": []}")
        let result = await solver.solve(query: "what is love", appID: "")
        XCTAssertEqual(result.failure, .noResult(suggestions: []))
    }

    func testBrokenReplyIsMalformed() async {
        attach()
        ai.generateJSONResult = .success("nope")
        let result = await solver.solve(query: "x", appID: "")
        XCTAssertEqual(result.failure, .malformed)
    }

    func testWithoutGeminiSetUpTheErrorIsMissingKeyAndNothingIsSent() async {
        let result = await solver.solve(query: "x", appID: "")
        XCTAssertEqual(result.failure, .missingKey)
        XCTAssertTrue(ai.generateJSONCalls.isEmpty)
    }

    func testAIFailuresAreMappedToSolveErrors() async {
        attach()
        let cases: [(AIError, SolveError)] = [
            (.offline, .network), (.timeout, .network), (.rateLimited, .rateLimited), (.quotaExhausted, .rateLimited),
            (.invalidAPIKey, .missingKey), (.noModelSelected, .missingKey), (.malformedResponse, .malformed),
        ]
        for (aiError, expected) in cases {
            ai.generateJSONResult = .failure(aiError)
            let result = await solver.solve(query: "x", appID: "")
            XCTAssertEqual(result.failure, expected, "\(aiError)")
        }
    }

    // MARK: Steps for a verified answer

    func testStepsPromptCarriesTheVerifiedAnswerAndKeepsIt() async throws {
        attach()
        ai.generateJSONResult = .success("{\"steps\": [\"Subtract 3 from both sides.\", \"Divide by 2.\"]}")
        let result = await solver.steps(query: "2x + 3 = 11", podID: "Result", stepsInput: "ai:x = 4", appID: "")
        let pod = try XCTUnwrap(result.success)

        let call = try XCTUnwrap(ai.generateJSONCalls.first)
        XCTAssertEqual(call.prompt, "Problem: 2x + 3 = 11\nVerified answer: x = 4")
        XCTAssertTrue(call.systemInstruction.contains("The answer is correct"))

        XCTAssertEqual(pod.id, "Result")
        XCTAssertTrue(pod.primary)
        XCTAssertEqual(pod.subpods.first?.plaintext, "x = 4", "the verified answer is kept, never rewritten")
        XCTAssertEqual(pod.subpods.last?.plaintext, "1. Subtract 3 from both sides.\n2. Divide by 2.")
        XCTAssertTrue(pod.hasSteps)
    }

    func testStepsForAWolframOfferAreNotGeminisJob() async {
        attach()
        let result = await solver.steps(query: "x", podID: "Result", stepsInput: "Result__Step-by-step solution", appID: "abc")
        XCTAssertEqual(result.failure, .noSteps)
        XCTAssertTrue(ai.generateJSONCalls.isEmpty)
    }

    func testEmptyStepsAreNoSteps() async {
        attach()
        ai.generateJSONResult = .success("{\"steps\": [\"  \", \"\"]}")
        let result = await solver.steps(query: "x", podID: "Result", stepsInput: "ai:x = 1", appID: "")
        XCTAssertEqual(result.failure, .noSteps)
    }

    func testStepsAreCappedInCountAndLength() {
        let many = (1...30).map { "step \($0)" }
        XCTAssertEqual(GeminiMathSolver.parseSteps("{\"steps\": \(String(data: try! JSONEncoder().encode(many), encoding: .utf8)!)}")?.count, GeminiMathSolver.maxSteps)
        let long = String(repeating: "a", count: 1_000)
        XCTAssertEqual(GeminiMathSolver.parseSteps("{\"steps\": [\"\(long)\"]}")?.first?.count, GeminiMathSolver.maxStepLength)
    }
}

final class CompositeMathSolverTests: XCTestCase {
    private var local: MockMathSolver!
    private var wolfram: MockMathSolver!
    private var gemini: MockMathSolver!
    private var solver: CompositeMathSolver!

    override func setUp() {
        local = MockMathSolver()
        wolfram = MockMathSolver()
        gemini = MockMathSolver()
        solver = CompositeMathSolver(local: local, wolfram: wolfram, gemini: gemini)
    }

    private func result(_ source: SolveSource) -> SolveResult {
        var value = SolveResult.sample()
        value.source = source
        return value
    }

    func testOnDeviceAnswerWinsAndNothingElseIsAsked() async {
        local.solveResults = [.success(result(.onDevice))]
        let outcome = await solver.solve(query: "x", appID: "abc")
        XCTAssertEqual(outcome.success?.source, .onDevice)
        XCTAssertTrue(wolfram.solveCalls.isEmpty)
        XCTAssertTrue(gemini.solveCalls.isEmpty)
    }

    func testWithoutAnAppIDWolframIsSkipped() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        gemini.solveResults = [.success(result(.gemini))]
        let outcome = await solver.solve(query: "x", appID: "")
        XCTAssertEqual(outcome.success?.source, .gemini)
        XCTAssertTrue(wolfram.solveCalls.isEmpty)
    }

    func testWolframIsTheSecondOpinionBeforeGemini() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        wolfram.solveResults = [.success(result(.wolfram))]
        let outcome = await solver.solve(query: "x", appID: "abc")
        XCTAssertEqual(outcome.success?.source, .wolfram)
        XCTAssertEqual(wolfram.solveCalls.first?.appID, "abc")
        XCTAssertTrue(gemini.solveCalls.isEmpty)
    }

    func testGeminiCatchesWhatWolframCannotDo() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        wolfram.solveResults = [.failure(.rateLimited)]
        gemini.solveResults = [.success(result(.gemini))]
        let outcome = await solver.solve(query: "x", appID: "abc")
        XCTAssertEqual(outcome.success?.source, .gemini)
    }

    func testWhenGeminiIsNotSetUpWolframsReasonIsReported() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        wolfram.solveResults = [.failure(.noResult(suggestions: ["x^2 - 4 = 0"]))]
        gemini.solveResults = [.failure(.missingKey)]
        let outcome = await solver.solve(query: "x2 -4", appID: "abc")
        XCTAssertEqual(outcome.failure, .noResult(suggestions: ["x^2 - 4 = 0"]), "its suggestions are the useful part")
    }

    func testGeminiNotSetUpAndNoWolframIsMissingKey() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        gemini.solveResults = [.failure(.missingKey)]
        let outcome = await solver.solve(query: "x", appID: "")
        XCTAssertEqual(outcome.failure, .missingKey)
    }

    func testGeminiNetworkFailureIsReportedAsIs() async {
        local.solveResults = [.failure(.noResult(suggestions: []))]
        gemini.solveResults = [.failure(.network)]
        let outcome = await solver.solve(query: "x", appID: "")
        XCTAssertEqual(outcome.failure, .network)
    }

    func testStepsGoToWhoeverTheOfferPointsAt() async {
        gemini.stepsResults = [.success(SolvePod(id: "Result", title: "Result", hasSteps: true))]
        let ai = await solver.steps(query: "x", podID: "Result", stepsInput: "ai:x = 1", appID: "abc")
        XCTAssertNotNil(ai.success)
        XCTAssertEqual(gemini.stepsCalls.first?.stepsInput, "ai:x = 1")
        XCTAssertTrue(wolfram.stepsCalls.isEmpty)

        wolfram.stepsResults = [.success(SolvePod(id: "Result", title: "Result", hasSteps: true))]
        let viaWolfram = await solver.steps(query: "x", podID: "Result", stepsInput: "Result__Step-by-step solution", appID: "abc")
        XCTAssertNotNil(viaWolfram.success)
        XCTAssertEqual(gemini.stepsCalls.count, 1)
    }

    func testWolframStepsWithoutAnAppIDAreNoSteps() async {
        let outcome = await solver.steps(query: "x", podID: "Result", stepsInput: "Result__Step-by-step solution", appID: "")
        XCTAssertEqual(outcome.failure, .noSteps)
        XCTAssertTrue(wolfram.stepsCalls.isEmpty)
    }
}
