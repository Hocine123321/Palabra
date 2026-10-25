import UIKit
import XCTest
@testable import Palabra

@MainActor
final class GeminiPhotoSolveTests: XCTestCase {
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
    {"readable": true, "solvable": true,
     "answer": "(a) x = -2 or x = 2\\n(b) x = 3", "steps": ["1. (a) x^2 = 4", "(a) x = +-2", "(b) 2x = 6", "(b) x = 3"],
     "title": "Two equations"}
    """

    func testThePhotoItselfGoesToGeminiAndTheProblemIsNeverTranscribed() async throws {
        attach()
        ai.imageResult = .success(solvedJSON)
        let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        XCTAssertNotNil(result.success)

        let call = try XCTUnwrap(ai.imageCalls.first)
        XCTAssertFalse(call.image.data.isEmpty, "the picture is sent, not just a request")
        XCTAssertEqual(call.image.mimeType, "image/jpeg")
        XCTAssertEqual(call.prompt, GeminiMathSolver.photoPrompt)
        XCTAssertTrue(call.systemInstruction.contains("every part"))
        XCTAssertTrue(call.systemInstruction.contains("Do not copy the problem out"))
        XCTAssertFalse(call.systemInstruction.contains("copy the whole problem"))
        XCTAssertTrue(call.systemInstruction.contains("Write the steps in English."))
        XCTAssertEqual((call.schema?["required"] as? [String])?.sorted(), ["answer", "readable", "solvable", "steps", "title"])
        XCTAssertEqual(call.schema?["propertyOrdering"] as? [String], ["readable", "solvable", "answer", "steps", "title"], "no transcription step in the schema")
        XCTAssertNil((call.schema?["properties"] as? [String: Any])?["problem"])
        XCTAssertTrue(ai.generateJSONCalls.isEmpty, "no separate text step")
    }

    func testAMultiPartAnswerKeepsEveryPartAndIsLabelledByTheTitle() async throws {
        attach()
        ai.imageResult = .success(solvedJSON)
        let outcome = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        let solved = try XCTUnwrap(outcome.success)
        XCTAssertEqual(solved.query, "Two equations")
        XCTAssertEqual(solved.fromPhoto, true)
        XCTAssertNil(solved.pods.first { $0.id == "Input" }, "no copy of the problem")
        XCTAssertEqual(solved.source, .gemini)
        XCTAssertFalse(solved.isFromWolfram)
        XCTAssertEqual(solved.answerText.components(separatedBy: "\n").prefix(2).map { $0 }, ["(a) x = -2 or x = 2", "(b) x = 3"])
        XCTAssertEqual(solved.answerPod?.hasSteps, true)
    }

    func testPhotoSolutionsAllowMoreStepsThanTypedOnes() throws {
        let steps = (1...18).map { "\"step \($0)\"" }.joined(separator: ",")
        let json = "{\"readable\":true,\"solvable\":true,\"answer\":\"a\",\"steps\":[\(steps)],\"title\":\"p\"}"
        let solved = try XCTUnwrap(GeminiMathSolver.parsePhotoSolution(json).success)
        let text = try XCTUnwrap(solved.answerPod?.subpods.last?.plaintext)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 18)
    }

    func testNoProblemInThePhotoIsReportedAsUnreadable() async {
        attach()
        ai.imageResult = .success(#"{"readable": false, "solvable": false, "answer": "", "steps": [], "title": ""}"#)
        let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        XCTAssertEqual(result.failure, .unreadablePhoto)
    }

    func testAReadableProblemWithoutAnAnswerIsUnsolved() async {
        attach()
        ai.imageResult = .success(#"{"readable": true, "solvable": false, "answer": "", "steps": [], "title": "hard thing"}"#)
        let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        XCTAssertEqual(result.failure, .unsolvedPhoto)
    }

    func testAMissingTitleGetsAPlainLabelAndLongOnesAreCapped() throws {
        let none = try XCTUnwrap(GeminiMathSolver.parsePhotoSolution(#"{"readable":true,"solvable":true,"answer":"4","steps":[],"title":" "}"#).success)
        XCTAssertEqual(none.query, GeminiMathSolver.photoFallbackTitle)
        let long = String(repeating: "t", count: 500)
        let capped = try XCTUnwrap(GeminiMathSolver.parsePhotoSolution("{\"readable\":true,\"solvable\":true,\"answer\":\"4\",\"steps\":[],\"title\":\"\(long)\"}").success)
        XCTAssertEqual(capped.query.count, GeminiMathSolver.maxPhotoTitleLength)
    }

    func testThePhotoInstructionAsksForABestAnswerInsteadOfARefusal() {
        let text = GeminiMathSolver.photoInstruction(language: .english)
        XCTAssertTrue(text.contains("Always give your best answer"))
        XCTAssertFalse(text.contains("never guess"), "a cautious model would refuse most photos")
    }

    func testGarbageReplyIsMalformed() async {
        attach()
        ai.imageResult = .success("not json")
        let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        XCTAssertEqual(result.failure, .malformed)
    }

    func testWithoutAKeyNothingIsSent() async {
        let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo())
        XCTAssertEqual(result.failure, .missingKey)
        attach()
        let bad = await solver.solvePhoto(imageData: Data("not an image".utf8))
        XCTAssertEqual(bad.failure, .unreadablePhoto)
        XCTAssertTrue(ai.imageCalls.isEmpty)
    }

    func testGeminiFailuresMapToTheSolveTabsErrors() async {
        attach()
        let cases: [(AIError, SolveError)] = [(.offline, .network), (.rateLimited, .rateLimited), (.modelUnavailable("x"), .missingKey)]
        for (error, expected) in cases {
            ai.imageResult = .failure(error)
            let result = await solver.solvePhoto(imageData: GeminiTextRecognizerTests.photo(width: 200, height: 100))
            XCTAssertEqual(result.failure, expected)
        }
    }

    func testPhotosForSolvingKeepMoreDetailThanPhotosForReading() throws {
        let big = GeminiTextRecognizerTests.photo(width: 4000, height: 3000)
        let solving = try XCTUnwrap(PhotoPreparer.prepare(big, maxPixelSize: PhotoPreparer.solvePixelSize))
        let reading = try XCTUnwrap(PhotoPreparer.prepare(big))
        let solvingSize = try XCTUnwrap(UIImage(data: solving.data)?.size)
        let readingSize = try XCTUnwrap(UIImage(data: reading.data)?.size)
        XCTAssertEqual(max(solvingSize.width, solvingSize.height), CGFloat(PhotoPreparer.solvePixelSize))
        XCTAssertEqual(max(readingSize.width, readingSize.height), CGFloat(PhotoPreparer.maxPixelSize))
    }
}

@MainActor
final class SolveModelPhotoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_644_400)
    private var solver: MockMathSolver!
    private var tool: SolveTool!

    override func setUp() {
        solver = MockMathSolver()
        tool = SolveTool(
            solver: solver,
            recognizer: MockTextRecognizer(result: .success("gemini text")),
            localRecognizer: MockTextRecognizer(result: .success("device text")),
            history: SwiftDataSolveRepository.inMemory(),
            usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-tests-\(UUID().uuidString)")!),
            keychain: KeychainStore(account: "wolfram-app-id-tests-\(UUID().uuidString)"),
            now: now
        )
    }

    private func model() -> SolveModel { SolveModel(tool: tool, now: { self.now }) }

    private func solved(_ query: String = "Two sums") -> SolveResult {
        SolveResult(query: query, pods: [
            SolvePod(id: "Result", title: "Result", primary: true, subpods: [SolveSubpod(plaintext: "(a) 4\n(b) 6")]),
        ], source: .gemini, fromPhoto: true)
    }

    func testSolvingAPhotoSavesTheAnswerAndThePhotoAndLeavesTheBoxAlone() async throws {
        solver.photoResults = [.success(solved())]
        let model = model()
        let photo = GeminiTextRecognizerTests.photo()
        let id = await model.solvePhoto(imageData: photo)
        let entry = try XCTUnwrap(tool.history.entry(id: try XCTUnwrap(id)))
        XCTAssertEqual(entry.query, "Two sums")
        XCTAssertEqual(entry.result?.fromPhoto, true)
        XCTAssertNotNil(tool.history.problemImage(id: entry.id), "the photo is kept as the problem")
        XCTAssertEqual(model.input, "", "nothing was transcribed into the box")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.error)
        XCTAssertEqual(tool.callsThisMonth, 0, "only Wolfram answers count")
        XCTAssertTrue(solver.solveCalls.isEmpty, "no second, text-only step")
    }

    func testTheSamePhotoAgainIsAnsweredFromTheSavedResult() async throws {
        solver.photoResults = [.success(solved())]
        let model = model()
        let photo = GeminiTextRecognizerTests.photo()
        let first = await model.solvePhoto(imageData: photo)
        let second = await model.solvePhoto(imageData: photo)
        XCTAssertEqual(first, second)
        XCTAssertEqual(solver.photoCalls, 1, "no second call for the same picture")
    }

    func testADifferentPhotoWithTheSameTitleDoesNotReplaceTheFirst() async throws {
        solver.photoResults = [.success(solved()), .success(solved())]
        let model = model()
        let first = await model.solvePhoto(imageData: GeminiTextRecognizerTests.photo(width: 120, height: 80))
        let second = await model.solvePhoto(imageData: GeminiTextRecognizerTests.photo(width: 200, height: 90))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(tool.history.entries(limit: 10).count, 2)
    }

    func testWhenGeminiCantBeUsedThePhotoIsReadAsTextInstead() async {
        for failure in [SolveError.missingKey, .network, .rateLimited] {
            tool.settings.photoMode = .sendToGemini
            solver.photoResults = [.failure(failure)]
            let model = model()
            let id = await model.solvePhoto(imageData: Data([1]))
            XCTAssertNil(id)
            XCTAssertEqual(model.input, "gemini text", "\(failure): the photo isn't wasted")
            XCTAssertEqual(model.photoNotice, "Gemini couldn't be reached, so the text was read on this device. Check it, then tap Solve.")
            XCTAssertNil(model.photoMessage, "a hint, not an error")
            XCTAssertNil(model.error)
        }
    }

    func testWithoutAKeyThePhotoIsReadHereAndGeminiIsNeverAsked() async {
        let link = GeminiLink() // nothing attached: no key or model
        tool = SolveTool(
            solver: solver,
            recognizer: MockTextRecognizer(result: .success("device text")),
            history: SwiftDataSolveRepository.inMemory(),
            usage: SolveUsage(defaults: UserDefaults(suiteName: "solve-tests-\(UUID().uuidString)")!),
            keychain: KeychainStore(account: "wolfram-app-id-tests-\(UUID().uuidString)"),
            geminiLink: link,
            now: now
        )
        let model = model()
        let id = await model.solvePhoto(imageData: Data([1]))
        XCTAssertNil(id)
        XCTAssertEqual(solver.photoCalls, 0)
        XCTAssertEqual(model.input, "device text")
        XCTAssertEqual(model.photoNotice, "No Gemini key or model is set, so the text was read on this device. Check it, then tap Solve.")
    }

    func testAPhotoWithNoProblemSaysSo() async {
        solver.photoResults = [.failure(.unreadablePhoto)]
        let model = model()
        let id = await model.solvePhoto(imageData: Data([1]))
        XCTAssertNil(id)
        XCTAssertEqual(model.photoMessage, RecognitionError.nothingFound.userMessage)
    }

    func testAnUnsolvedPhotoIsReadAsTextOnTheDeviceForChecking() async {
        solver.photoResults = [.failure(.unsolvedPhoto)]
        let model = model()
        let id = await model.solvePhoto(imageData: Data([1]))
        XCTAssertNil(id)
        XCTAssertEqual(model.input, "gemini text")
        XCTAssertEqual(model.photoNotice, "Gemini couldn't solve the photo, so the text was read on this device. Check it, then tap Solve.")
        XCTAssertNil(model.error)
    }

    func testOtherFailuresAreShownAsErrors() async {
        solver.photoResults = [.failure(.noResult(suggestions: []))]
        let model = model()
        _ = await model.solvePhoto(imageData: Data([1]))
        XCTAssertEqual(model.error, .noResult(suggestions: []))
    }

    func testCancellingASolvingPhotoSavesNothing() async {
        solver.photoResults = [.success(solved())]
        let model = model()
        let task = Task { await model.solvePhoto(imageData: Data([1])) }
        task.cancel()
        let id = await task.value
        XCTAssertNil(id)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(tool.history.entries(limit: 10).isEmpty)
    }

    func testTheReadingModesPickTheirOwnReader() async {
        let model = model()
        tool.settings.photoMode = .readText
        await model.recognize(imageData: Data([1]))
        XCTAssertEqual(model.input, "gemini text")
        tool.settings.photoMode = .readOnDevice
        await model.recognize(imageData: Data([1]))
        XCTAssertEqual(model.input, "device text", "on-device mode never asks Gemini")
    }
}

@MainActor
final class SolveSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "solve-settings-\(UUID().uuidString)")! }

    func testDefaultsSendPhotosToGeminiAndSolveOnDeviceFirst() {
        let settings = SolveSettings()
        XCTAssertEqual(settings.photoMode, .sendToGemini)
        XCTAssertTrue(settings.useOnDeviceEngine)
        XCTAssertNil(settings.modelID)
    }

    func testSettingsArePersisted() {
        let defaults = defaults()
        let store = SolveSettingsStore(defaults: defaults)
        var changed = store.value
        changed.photoMode = .readOnDevice
        changed.useOnDeviceEngine = false
        changed.modelID = "models/x"
        store.value = changed
        XCTAssertEqual(SolveSettingsStore(defaults: defaults).value, changed)
    }

    func testAnUnknownSavedPhotoModeFallsBackToTheDefault() throws {
        let data = Data(#"{"photoMode":"somethingNew","useOnDeviceEngine":false}"#.utf8)
        let settings = try JSONDecoder().decode(SolveSettings.self, from: data)
        XCTAssertEqual(settings.photoMode, .sendToGemini)
        XCTAssertFalse(settings.useOnDeviceEngine)
    }

    func testTheToolSavesWhatThePageChanges() {
        let defaults = defaults()
        let tool = SolveTool(
            solver: MockMathSolver(), recognizer: MockTextRecognizer(result: .success("")),
            history: SwiftDataSolveRepository.inMemory(), settingsStore: SolveSettingsStore(defaults: defaults)
        )
        tool.settings.photoMode = .readText
        XCTAssertEqual(SolveSettingsStore(defaults: defaults).value.photoMode, .readText)
    }

    func testTurningTheOnDeviceEngineOffSendsEverythingToGemini() async {
        let local = MockMathSolver(), gemini = MockMathSolver()
        local.solveResults = [.success(.sample())]
        gemini.solveResults = [.success(.sample(query: "from gemini"))]
        let on = CompositeMathSolver(local: local, wolfram: nil, gemini: gemini, useLocal: { true })
        let onResult = await on.solve(query: "x", appID: "")
        XCTAssertEqual(onResult.success?.query, "x^2-4=0")
        XCTAssertEqual(gemini.solveCalls.count, 0)

        local.solveResults = [.success(.sample())]
        let off = CompositeMathSolver(local: local, wolfram: nil, gemini: gemini, useLocal: { false })
        let offResult = await off.solve(query: "x", appID: "")
        XCTAssertEqual(offResult.success?.query, "from gemini")
        XCTAssertEqual(local.solveCalls.count, 1, "the on-device engine wasn't asked the second time")
    }

    func testPhotosAlwaysGoToGemini() async {
        let local = MockMathSolver(), gemini = MockMathSolver()
        gemini.photoResults = [.success(.sample())]
        let composite = CompositeMathSolver(local: local, wolfram: nil, gemini: gemini)
        _ = await composite.solvePhoto(imageData: Data([1]))
        XCTAssertEqual(gemini.photoCalls, 1)
        XCTAssertEqual(local.photoCalls, 0)
    }
}
