import XCTest
@testable import Palabra

final class WolframSolverTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private let json = #"{"queryresult":{"success":true,"pods":[{"id":"Input","title":"Input","subpods":[{"plaintext":"1+1","img":{"src":"https://img.example/in.gif","width":50,"height":20}}]},{"id":"Result","title":"Result","primary":true,"subpods":[{"plaintext":"2","img":{"src":"https://img.example/r.gif","width":20,"height":20}}],"states":[{"name":"Step-by-step solution","input":"Result__Step-by-step solution"}]}]}}"#
    private let stepsJSON = #"{"queryresult":{"success":true,"pods":[{"id":"Result","title":"Result","subpods":[{"plaintext":"2"},{"title":"Possible intermediate steps","plaintext":"1 + 1 = 2","img":{"src":"https://img.example/s.gif","width":50,"height":50}}]}]}}"#
    private let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])

    private func solver() -> WolframSolver { WolframSolver(session: MockURLProtocol.session()) }

    func testRequestCarriesTheAppIDQueryAndFormat() async throws {
        let seen = Box<[URL]>([])
        MockURLProtocol.handler = { [json, gif] request in
            let url = request.url!
            seen.value.append(url)
            return url.host == "api.wolframalpha.com" ? (200, Data(json.utf8)) : (200, gif)
        }
        _ = await solver().solve(query: "1+1", appID: "KEY123")
        let api = try XCTUnwrap(seen.value.first { $0.host == "api.wolframalpha.com" })
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: api, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["appid"], "KEY123")
        XCTAssertEqual(items["input"], "1+1")
        XCTAssertEqual(items["output"], "json")
        XCTAssertEqual(items["format"], "image,plaintext")
        XCTAssertNil(items["podstate"])
    }

    func testImagesAreDownloadedAndKept() async throws {
        MockURLProtocol.handler = { [json, gif] request in
            request.url!.host == "api.wolframalpha.com" ? (200, Data(json.utf8)) : (200, gif)
        }
        let result = try await solver().solve(query: "1+1", appID: "K").get()
        XCTAssertEqual(result.pods[0].subpods[0].imageData, gif)
        XCTAssertEqual(result.pods[1].subpods[0].imageData, gif)
        XCTAssertEqual(result.pods[1].stepsInput, "Result__Step-by-step solution")
    }

    func testAFailedImageDownloadKeepsThePlainText() async throws {
        MockURLProtocol.handler = { [json] request in
            request.url!.host == "api.wolframalpha.com" ? (200, Data(json.utf8)) : (404, Data())
        }
        let result = try await solver().solve(query: "1+1", appID: "K").get()
        XCTAssertNil(result.pods[1].subpods[0].imageData)
        XCTAssertEqual(result.answerText, "2")
    }

    func testOversizedImagesAreDropped() async throws {
        let big = Data(count: WolframSolver.maxImageBytes + 1)
        MockURLProtocol.handler = { [json] request in
            request.url!.host == "api.wolframalpha.com" ? (200, Data(json.utf8)) : (200, big)
        }
        let result = try await solver().solve(query: "1+1", appID: "K").get()
        XCTAssertNil(result.pods[1].subpods[0].imageData)
    }

    func testStatusCodesMapToErrors() async {
        for (status, expected) in [(403, SolveError.invalidKey), (401, .invalidKey), (429, .rateLimited), (503, .network)] {
            MockURLProtocol.handler = { _ in (status, Data()) }
            let result = await solver().solve(query: "1+1", appID: "K")
            XCTAssertEqual(result.failure, expected, "status \(status)")
        }
    }

    func testConnectionFailureIsNetwork() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let result = await solver().solve(query: "1+1", appID: "K")
        XCTAssertEqual(result.failure, .network)
    }

    func testStepsSendThePodStateAndReturnThePod() async throws {
        let seen = Box<[URL]>([])
        MockURLProtocol.handler = { [stepsJSON, gif] request in
            let url = request.url!
            seen.value.append(url)
            return url.host == "api.wolframalpha.com" ? (200, Data(stepsJSON.utf8)) : (200, gif)
        }
        let pod = try await solver().steps(query: "1+1", podID: "Result", stepsInput: "Result__Step-by-step solution", appID: "K").get()
        XCTAssertTrue(pod.hasSteps)
        XCTAssertEqual(pod.subpods.last?.title, "Possible intermediate steps")
        XCTAssertEqual(pod.subpods.last?.imageData, gif)
        let api = try XCTUnwrap(seen.value.first { $0.host == "api.wolframalpha.com" })
        let podstate = URLComponents(url: api, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "podstate" }?.value
        XCTAssertEqual(podstate, "Result__Step-by-step solution")
    }

    func testStepsThatAreNotInTheAnswerAreNoSteps() async {
        MockURLProtocol.handler = { [json] _ in (200, Data(json.utf8)) }
        let result = await solver().steps(query: "1+1", podID: "Result", stepsInput: "x", appID: "K")
        XCTAssertEqual(result.failure, .noSteps)
    }

    func testNoResultForStepsBecomesNoSteps() async {
        MockURLProtocol.handler = { _ in (200, Data(#"{"queryresult":{"success":false}}"#.utf8)) }
        let result = await solver().steps(query: "1+1", podID: "Result", stepsInput: "x", appID: "K")
        XCTAssertEqual(result.failure, .noSteps)
    }
}
