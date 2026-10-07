import XCTest
@testable import Palabra

final class ArtifactEnvelopeTests: XCTestCase {
    private let header = #"{"kind":"spec","title":"Weekdays","requests":["library.words"]}"#
    private let payload = #"{"blocks":[{"type":"text","text":"hi"}]}"#

    private func envelope(header: String? = nil, payload: String? = nil, end: Bool = true) -> String {
        "\(header ?? self.header)\n---PAYLOAD---\n\(payload ?? self.payload)\n" + (end ? "---END---" : "")
    }

    private func parsed(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> ArtifactEnvelope? {
        guard case .success(let value) = ArtifactEnvelopeParser.parse(text) else {
            XCTFail("parse failed", file: file, line: line)
            return nil
        }
        return value
    }

    func testParsesWellFormedEnvelope() {
        let value = parsed(envelope())
        XCTAssertEqual(value?.kind, .spec)
        XCTAssertEqual(value?.title, "Weekdays")
        XCTAssertEqual(value?.requests, ["library.words"])
        XCTAssertEqual(value?.payload, payload)
    }

    func testMissingEndMarkerIsTruncated() {
        XCTAssertEqual(ArtifactEnvelopeParser.parse(envelope(end: false)), .failure(.truncated))
    }

    func testMissingPayloadMarkerIsMalformed() {
        guard case .failure(.malformedEnvelope) = ArtifactEnvelopeParser.parse(header) else {
            return XCTFail("expected malformedEnvelope")
        }
    }

    func testEmptyPayloadIsMalformed() {
        guard case .failure(.malformedEnvelope) = ArtifactEnvelopeParser.parse("\(header)\n---PAYLOAD---\n\n---END---") else {
            return XCTFail("expected malformedEnvelope")
        }
    }

    func testHeaderNotJSONIsMalformed() {
        guard case .failure(.malformedEnvelope) = ArtifactEnvelopeParser.parse(envelope(header: "hello there")) else {
            return XCTFail("expected malformedEnvelope")
        }
    }

    func testUnknownKindIsMalformed() {
        guard case .failure(.malformedEnvelope) = ArtifactEnvelopeParser.parse(envelope(header: #"{"kind":"video","title":"x"}"#)) else {
            return XCTFail("expected malformedEnvelope")
        }
    }

    func testHeaderInsideCodeFenceWithChatterIsAccepted() {
        let text = "Here you go:\n```json\n\(header)\n```\n---PAYLOAD---\n\(payload)\n---END---"
        XCTAssertEqual(parsed(text)?.title, "Weekdays")
    }

    func testPayloadInsideCodeFenceIsUnwrapped() {
        let text = "\(header)\n---PAYLOAD---\n```json\n\(payload)\n```\n---END---"
        XCTAssertEqual(parsed(text)?.payload, payload)
    }

    func testTitleIsTrimmedCappedAndDefaulted() {
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(parsed(envelope(header: #"{"kind":"spec","title":"  \#(long)  "}"#))?.title.count, ArtifactGeneratorLimits.maxTitleLength)
        XCTAssertEqual(parsed(envelope(header: #"{"kind":"spec","title":"   "}"#))?.title, "Untitled")
        XCTAssertEqual(parsed(envelope(header: #"{"kind":"spec"}"#))?.title, "Untitled")
    }

    func testRequestsDefaultToEmptyAndSkipNonStrings() {
        XCTAssertEqual(parsed(envelope(header: #"{"kind":"spec","title":"t"}"#))?.requests, [])
        XCTAssertEqual(parsed(envelope(header: #"{"kind":"spec","title":"t","requests":["a",1,"b"]}"#))?.requests, ["a", "b"])
    }

    func testUserMessagesAreNonEmpty() {
        let errors: [ArtifactGenError] = [.ai(.offline), .truncated, .malformedEnvelope("x"), .invalidSpec("x"), .kindNotAvailable, .tooLargeToExtend]
        for error in errors { XCTAssertFalse(error.userMessage.isEmpty) }
    }
}
