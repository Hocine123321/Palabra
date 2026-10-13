import XCTest
@testable import Palabra

/// Runs the real bundled engine (nerdamer + solver.js in JavaScriptCore): these check what a person would actually get.
final class LocalMathSolverTests: XCTestCase {
    private let solver = LocalMathSolver()

    private func answer(_ query: String, file: StaticString = #filePath, line: UInt = #line) async -> SolveResult? {
        let result = await solver.solve(query: query, appID: "")
        guard case .success(let value) = result else {
            XCTFail("expected an answer for \(query), got \(result)", file: file, line: line)
            return nil
        }
        return value
    }

    private func isUnsupported(_ query: String) async -> Bool {
        if case .failure(.noResult) = await solver.solve(query: query, appID: "") { return true }
        return false
    }

    func testQuadraticListsBothRoots() async {
        let result = await answer("x^2 - 4 = 0")
        XCTAssertEqual(result?.answerText, "x = -2 or x = 2")
    }

    func testLinearEquation() async {
        let result = await answer("2x + 3 = 11")
        XCTAssertEqual(result?.answerText, "x = 4")
    }

    func testIrrationalRootsAlsoGetADecimalPod() async {
        let result = await answer("x^2 - 2 = 0")
        XCTAssertEqual(result?.answerText, "x = -sqrt(2) or x = sqrt(2)")
        let decimal = result?.pods.first { $0.title == "Decimal approximation" }
        XCTAssertEqual(decimal?.plainText, "x ≈ -1.414213562 or x ≈ 1.414213562")
    }

    func testLinearSystem() async {
        let result = await answer("x + y = 5; x - y = 1")
        XCTAssertEqual(result?.answerText, "x = 3, y = 2")
    }

    func testDerivativeIntegralAndLimit() async {
        let derivative = await answer("derivative of sin(x) x^2")
        XCTAssertTrue(derivative?.answerText.contains("cos(x)") ?? false)
        let definite = await answer("integral of x^2 from 0 to 3")
        XCTAssertEqual(definite?.answerText, "9")
        let indefinite = await answer("integrate x^2")
        XCTAssertEqual(indefinite?.answerText, "(1/3)*x^3 + C")
        let limit = await answer("limit of sin(x)/x as x -> 0")
        XCTAssertEqual(limit?.answerText, "1")
    }

    func testArithmeticIsExactWithADecimalPod() async {
        let result = await answer("3/4 + 5/6")
        XCTAssertEqual(result?.answerText, "19/12")
        XCTAssertEqual(result?.pods.first { $0.title == "Decimal approximation" }?.plainText, "1.583333333")
    }

    func testFactoringAndExpanding() async {
        let factored = await answer("factor x^3 - 1")
        XCTAssertEqual(factored?.answerText, "(-1+x)*(1+x+x^2)")
        let expanded = await answer("expand (x+1)^3")
        XCTAssertEqual(expanded?.answerText, "1+3x+3x^2+x^3")
    }

    func testResultShapeOffersGeminiStepsForTheVerifiedAnswer() async {
        let result = await answer("x^2 - 4 = 0")
        XCTAssertEqual(result?.source, .onDevice)
        XCTAssertEqual(Array((result?.pods.map(\.id) ?? []).prefix(2)), ["Input", "Result"])
        XCTAssertEqual(result?.answerPod?.stepsInput, "ai:x = -2 or x = 2")
        XCTAssertEqual(result?.answerPod?.stepsAreAIWritten, true)
    }

    /// The engine only answers what it can check; everything else is left to Gemini.
    func testWhatItCannotVouchForIsUnsupported() async {
        let queries = ["x^2 - 4 > 0", "sin(x) = 1/2", "e^x = 5", "x^5 - x - 1 = 0", "log(100)", "10 mod 3", "100 degrees", "integral of 1/x^2 from -1 to 1", "limit of 1/x as x -> 0", "gibberish ((", "x + y = 1; x + y = 2"]
        for query in queries {
            let unsupported = await isUnsupported(query)
            XCTAssertTrue(unsupported, "\(query) should be left to Gemini")
        }
    }

    func testStepsAreNotTheEnginesJob() async {
        let result = await solver.steps(query: "x", podID: "Result", stepsInput: "ai:x", appID: "")
        XCTAssertEqual(result.failure, .noSteps)
    }

    func testEngineParseRejectsEmptyAndBrokenPayloads() {
        XCTAssertEqual(LocalMathEngine.parse(Data("{\"ok\":false,\"reason\":\"unsupported\"}".utf8)), .unsupported)
        XCTAssertEqual(LocalMathEngine.parse(Data("{\"ok\":true,\"answer\":\"  \"}".utf8)), .unsupported)
        XCTAssertEqual(LocalMathEngine.parse(Data("not json".utf8)), .unsupported)
    }
}
