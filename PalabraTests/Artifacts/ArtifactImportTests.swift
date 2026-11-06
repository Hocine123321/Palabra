import XCTest
@testable import Palabra

final class ArtifactImportTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("storage.set", .local),
    ])

    private func importText(_ text: String, expectedKind: ArtifactKind? = nil, settingKB: Int = ArtifactOutputBudget.defaultKB) -> Result<ArtifactDraft, ArtifactGenError> {
        ArtifactGenerator(ai: MockAIClient(), registry: registry, allowedKinds: [.spec, .app], maxOutputKB: settingKB)
            .importDraft(text, fixedTitle: nil, expectedKind: expectedKind, userPrompt: "asked")
    }

    private func draft(_ result: Result<ArtifactDraft, ArtifactGenError>, file: StaticString = #filePath, line: UInt = #line) -> ArtifactDraft? {
        if case .success(let draft) = result { return draft }
        XCTFail("expected success, got \(result)", file: file, line: line)
        return nil
    }

    private func isInvalidApp(_ result: Result<ArtifactDraft, ArtifactGenError>) -> Bool {
        if case .failure(.invalidApp) = result { return true }
        return false
    }

    private let appEnvelope = #"{"kind":"app","title":"Verbs","requests":["library.words"]}"# + "\n---PAYLOAD---\n<html><body>hi</body></html>\n---END---"

    func testEnvelopeIsAccepted() {
        let result = draft(importText(appEnvelope))
        XCTAssertEqual(result?.kind, .app)
        XCTAssertEqual(result?.title, "Verbs")
        XCTAssertEqual(result?.requests, ["library.words"])
    }

    func testFencedEnvelopeIsAccepted() {
        XCTAssertEqual(draft(importText("```text\n" + appEnvelope + "\n```"))?.kind, .app)
    }

    func testBareHTMLBecomesAnAppWithTitleFromTitleTag() {
        let html = "<!doctype html><html><head><title>Verb Trainer</title></head><body>x</body></html>"
        let result = draft(importText(html))
        XCTAssertEqual(result?.kind, .app)
        XCTAssertEqual(result?.title, "Verb Trainer")
    }

    func testChatProseAroundFencedHTMLIsStripped() {
        let text = "Here is your app:\n```html\n<html><body>x</body></html>\n```\nEnjoy!"
        let result = draft(importText(text))
        let html = result.map { String(decoding: $0.payload, as: UTF8.self) } ?? ""
        XCTAssertTrue(html.hasPrefix("<html"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }

    func testRequestsAreInferredAndFilteredToRegisteredCapabilities() {
        let html = #"<html><script>palabra.call("library.words", {}); palabra.call('made.up');</script></html>"#
        XCTAssertEqual(draft(importText(html))?.requests, ["library.words"])
    }

    func testExternalURLAndLocalStorageStillRejected() {
        XCTAssertTrue(isInvalidApp(importText(#"<html><script src="https://x.example/a.js"></script></html>"#)))
        XCTAssertTrue(isInvalidApp(importText("<html><script>localStorage.a = 1</script></html>")))
    }

    func testAppAtTheStorageCeilingIsAcceptedAndOneOverIsRejected() {
        let limit = ArtifactLimits.maxPayloadBytes
        let pad = limit - "<html></html>".utf8.count
        let fits = "<html>" + String(repeating: "a", count: pad) + "</html>"
        XCTAssertNotNil(draft(importText(fits)))
        XCTAssertTrue(isInvalidApp(importText(fits + "a")))
    }

    func testImportAcceptsAPageFarAboveTheInAppCap() {
        // 500 KB: far over Gemini's 128 KB maximum, well inside the 2 MB an external page may be.
        let html = "<html>" + String(repeating: "a", count: 500_000) + "</html>"
        XCTAssertNotNil(draft(importText(html)))
    }

    func testImportIgnoresTheInAppGeminiSizeSetting() {
        let html = "<html>" + String(repeating: "a", count: 100_000) + "</html>"
        XCTAssertNotNil(draft(importText(html, settingKB: ArtifactOutputBudget.minKB)))
    }

    func testHugePasteIsRejectedWithoutParsing() {
        let huge = String(repeating: "a", count: ArtifactImport.maxInputBytes + 1)
        XCTAssertTrue(isInvalidApp(importText(huge)))
    }

    func testNoHTMLAndNoEnvelopeIsMalformed() {
        if case .failure(.malformedEnvelope) = importText("hello") { return }
        XCTFail("expected malformedEnvelope")
    }

    func testExpectedKindMismatchFails() {
        let spec = #"{"kind":"spec","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + #"{"blocks":[{"type":"text","text":"x"}]}"# + "\n---END---"
        if case .failure(.malformedEnvelope) = importText(spec, expectedKind: .app) { return }
        XCTFail("expected malformedEnvelope")
    }

    func testSpecEnvelopeIsAcceptedWithNoExpectedKind() {
        let spec = #"{"kind":"spec","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + #"{"blocks":[{"type":"text","text":"x"}]}"# + "\n---END---"
        XCTAssertEqual(draft(importText(spec))?.kind, .spec)
    }
}
