import XCTest
@testable import Palabra

final class WolframParserTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let success = """
    {"queryresult":{"success":true,"error":false,"numpods":3,"pods":[
      {"title":"Input","id":"Input","position":100,"subpods":[{"title":"","plaintext":"x^2 - 4 = 0","img":{"src":"https://www4b.wolframalpha.com/Calculate/MSP/in.gif","width":120,"height":30}}]},
      {"title":"Results","id":"Result","primary":true,"subpods":[{"title":"","plaintext":"x = -2","img":{"src":"https://www4b.wolframalpha.com/Calculate/MSP/r1.gif","width":"60","height":"20"}},{"title":"","plaintext":"x = 2"}],
       "states":[{"name":"Step-by-step solution","input":"Result__Step-by-step solution"}]},
      {"title":"Plot","id":"Plot","subpods":[{"title":"","plaintext":"","img":{"src":"http://insecure.example/plot.gif","width":300,"height":200}}]}
    ]}}
    """

    func testParsesPodsPlaintextAndSizes() throws {
        let parsed = try WolframParser.parse(data(success), query: "x^2-4=0").get()
        let result = parsed.result
        XCTAssertEqual(result.query, "x^2-4=0")
        XCTAssertEqual(result.interpretation, "x^2 - 4 = 0")
        XCTAssertEqual(result.pods.map(\.id), ["Input", "Result", "Plot"])
        XCTAssertEqual(result.answerPod?.id, "Result")
        XCTAssertEqual(result.answerText, "x = -2\nx = 2")
        XCTAssertEqual(result.pods[1].subpods[0].imageWidth, 60, "sizes may arrive as strings")
        XCTAssertEqual(result.otherPods.map(\.id), ["Plot"])
    }

    func testOnlyHTTPSImageURLsAreKept() throws {
        let parsed = try WolframParser.parse(data(success), query: "q").get()
        XCTAssertEqual(parsed.imageURLs[0].first??.host, "www4b.wolframalpha.com")
        XCTAssertNil(parsed.imageURLs[1][1], "no image")
        XCTAssertNil(parsed.imageURLs[2][0], "http is refused")
    }

    func testStepsOfferComesFromThePodStates() throws {
        let result = try WolframParser.parse(data(success), query: "q").get().result
        XCTAssertEqual(result.pods[1].stepsInput, "Result__Step-by-step solution")
        XCTAssertFalse(result.pods[1].hasSteps)
        XCTAssertNil(result.pods[0].stepsInput)
    }

    func testNestedStatesAreSearched() throws {
        let json = #"{"queryresult":{"success":true,"pods":[{"id":"Result","title":"R","subpods":[{"plaintext":"1"}],"states":[{"name":"Show all","states":[{"name":"Step-by-step solution","input":"R__Step"}]}]}]}}"#
        XCTAssertEqual(try WolframParser.parse(data(json), query: "q").get().result.pods[0].stepsInput, "R__Step")
    }

    func testAPodThatAlreadyHasStepsOffersNoMore() throws {
        let json = #"{"queryresult":{"success":true,"pods":[{"id":"Result","title":"R","subpods":[{"plaintext":"x=2"},{"title":"Possible intermediate steps","plaintext":"x^2=4"}],"states":[{"name":"Step-by-step solution","input":"R__Step"}]}]}}"#
        let pod = try WolframParser.parse(data(json), query: "q").get().result.pods[0]
        XCTAssertTrue(pod.hasSteps)
        XCTAssertNil(pod.stepsInput)
    }

    func testNoInterpretationGivesSuggestionsFromAnObject() {
        let json = #"{"queryresult":{"success":false,"error":false,"didyoumeans":{"val":"x^2","score":"0.9"}}}"#
        XCTAssertEqual(WolframParser.parse(data(json), query: "q").failure, .noResult(suggestions: ["x^2"]))
    }

    func testSuggestionsFromAnArrayAreCappedAtThree() {
        let json = #"{"queryresult":{"success":false,"didyoumeans":[{"val":"a"},{"val":"b"},{"val":"c"},{"val":"d"}]}}"#
        XCTAssertEqual(WolframParser.parse(data(json), query: "q").failure, .noResult(suggestions: ["a", "b", "c"]))
    }

    func testInvalidAppIDIsRecognized() {
        let json = #"{"queryresult":{"success":false,"error":{"code":"1","msg":"Invalid appid"}}}"#
        XCTAssertEqual(WolframParser.parse(data(json), query: "q").failure, .invalidKey)
    }

    func testOtherErrorsAreMalformed() {
        XCTAssertEqual(WolframParser.parse(data(#"{"queryresult":{"error":true}}"#), query: "q").failure, .malformed)
        XCTAssertEqual(WolframParser.parse(data("not json"), query: "q").failure, .malformed)
        XCTAssertEqual(WolframParser.parse(data("{}"), query: "q").failure, .malformed)
    }

    func testSuccessWithoutPodsIsNoResult() {
        XCTAssertEqual(WolframParser.parse(data(#"{"queryresult":{"success":true,"pods":[]}}"#), query: "q").failure, .noResult(suggestions: []))
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
