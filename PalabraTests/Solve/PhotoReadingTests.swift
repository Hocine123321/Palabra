import UIKit
import XCTest
@testable import Palabra

@MainActor
final class GeminiTextRecognizerTests: XCTestCase {
    private let model = AIModel(id: "models/gemini-test", displayName: "Test", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    private var ai: MockAIClient!
    private var link: GeminiLink!
    private var recognizer: GeminiTextRecognizer!

    override func setUp() {
        ai = MockAIClient()
        link = GeminiLink()
        recognizer = GeminiTextRecognizer(link: link)
    }

    private func attach() {
        let ai = self.ai!, model = self.model
        link.attach { GeminiLink.Credentials(ai: ai, apiKey: "key", model: model, language: .english) }
    }

    nonisolated static func photo(width: Int = 3000, height: Int = 2000) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testSendsThePhotoWithTheCopyInstructionAndSchema() async throws {
        attach()
        ai.imageResult = .success(#"{"found": true, "text": "  x^2 - 4 = 0 \n"}"#)
        let result = await recognizer.recognize(imageData: Self.photo())
        XCTAssertEqual(result.success, "x^2 - 4 = 0")

        let call = try XCTUnwrap(ai.imageCalls.first)
        XCTAssertEqual(call.prompt, GeminiTextRecognizer.prompt)
        XCTAssertEqual(call.systemInstruction, GeminiTextRecognizer.instruction)
        XCTAssertEqual(call.image.mimeType, "image/jpeg")
        XCTAssertFalse(call.image.data.isEmpty, "the picture itself is sent, not just a request")
        let properties = call.schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["found"])
        XCTAssertNotNil(properties?["text"])
    }

    func testWithoutCredentialsIsUnavailableAndNothingIsSent() async {
        let result = await recognizer.recognize(imageData: Self.photo())
        XCTAssertEqual(result.failure, .unavailable)
        XCTAssertTrue(ai.imageCalls.isEmpty)
    }

    func testNotAPhotoIsUnreadableAndNothingIsSent() async {
        attach()
        let result = await recognizer.recognize(imageData: Data("not an image".utf8))
        XCTAssertEqual(result.failure, .unreadable)
        XCTAssertTrue(ai.imageCalls.isEmpty)
    }

    func testAnyAIFailureIsUnavailableSoTheFallbackRuns() async {
        attach()
        for error in [AIError.offline, .rateLimited, .timeout, .invalidAPIKey, .blocked(nil)] {
            ai.imageResult = .failure(error)
            let result = await recognizer.recognize(imageData: Self.photo(width: 200, height: 100))
            XCTAssertEqual(result.failure, .unavailable, "\(error)")
        }
    }

    func testParsing() {
        XCTAssertEqual(GeminiTextRecognizer.parse(#"{"found": false, "text": ""}"#).failure, .nothingFound)
        XCTAssertEqual(GeminiTextRecognizer.parse(#"{"found": true, "text": "   "}"#).failure, .nothingFound)
        XCTAssertEqual(GeminiTextRecognizer.parse("nope").failure, .unavailable)
        XCTAssertEqual(GeminiTextRecognizer.parse(#"{"text": "2+2"}"#).success, "2+2", "a missing `found` is trusted when there is text")
        let long = String(repeating: "x", count: 5_000)
        XCTAssertEqual(GeminiTextRecognizer.parse(#"{"found": true, "text": "\#(long)"}"#).success?.count, GeminiTextRecognizer.maxTextLength)
    }
}

final class FallbackTextRecognizerTests: XCTestCase {
    private func chain(_ primary: Result<String, RecognitionError>, _ fallback: Result<String, RecognitionError>) -> FallbackTextRecognizer {
        FallbackTextRecognizer(primary: MockTextRecognizer(result: primary), fallback: MockTextRecognizer(result: fallback))
    }

    func testThePrimaryWinsWhenItReads() async {
        let result = await chain(.success("gemini"), .success("vision")).recognize(imageData: Data())
        XCTAssertEqual(result.success, "gemini")
    }

    func testAnUnavailablePrimaryFallsBack() async {
        let result = await chain(.failure(.unavailable), .success("vision")).recognize(imageData: Data())
        XCTAssertEqual(result.success, "vision")
    }

    func testNothingFoundByThePrimaryStillTriesTheFallback() async {
        let result = await chain(.failure(.nothingFound), .success("vision")).recognize(imageData: Data())
        XCTAssertEqual(result.success, "vision")
    }

    func testNothingFoundByBothIsNothingFound() async {
        let result = await chain(.failure(.nothingFound), .failure(.unreadable)).recognize(imageData: Data())
        XCTAssertEqual(result.failure, .nothingFound)
    }

    func testBothFailingReportsTheFallbacksError() async {
        let result = await chain(.failure(.unavailable), .failure(.unreadable)).recognize(imageData: Data())
        XCTAssertEqual(result.failure, .unreadable)
    }
}

final class PhotoPreparerTests: XCTestCase {
    func testShrinksALargePhotoToAJPEGWithinTheLimit() throws {
        let original = GeminiTextRecognizerTests.photo(width: 4000, height: 3000)
        let prepared = try XCTUnwrap(PhotoPreparer.prepare(original))
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        let image = try XCTUnwrap(UIImage(data: prepared.data))
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        XCTAssertLessThanOrEqual(longest, CGFloat(PhotoPreparer.maxPixelSize))
        XCTAssertGreaterThan(longest, 1000, "still big enough to read small print")
        XCTAssertLessThan(prepared.data.count, original.count)
    }

    func testASmallPhotoIsNotEnlarged() throws {
        let prepared = try XCTUnwrap(PhotoPreparer.prepare(GeminiTextRecognizerTests.photo(width: 300, height: 200)))
        let image = try XCTUnwrap(UIImage(data: prepared.data))
        XCTAssertLessThanOrEqual(image.size.width * image.scale, 300)
    }

    func testGarbageIsNil() {
        XCTAssertNil(PhotoPreparer.prepare(Data("nope".utf8)))
        XCTAssertNil(PhotoPreparer.prepare(Data()))
    }
}
