import XCTest
@testable import Palabra

final class ArtifactCapabilityScanTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("words.add", .write),
        makeCapability("ai.generate", .ai),
        makeCapability("storage.get", .local),
    ])

    private func scan(_ html: String) -> [String] { ArtifactCapabilityScan.names(in: html, registry: registry) }

    func testLiteralCallsAreFound() {
        XCTAssertEqual(scan(#"<script>palabra.call("library.words", {})</script>"#), ["library.words"])
        XCTAssertEqual(scan("<script>palabra.call('words.add', {})</script>"), ["words.add"])
    }

    /// The reported bug: a page that reaches a capability another way was never asked about, so its calls failed as "not allowed".
    func testIndirectUsesAreFoundToo() {
        XCTAssertEqual(scan(#"<script>const CAP = "library.words"; palabra.call(CAP, {})</script>"#), ["library.words"])
        XCTAssertEqual(scan("<script>api(`words.add`)</script>"), ["words.add"])
        XCTAssertEqual(scan(#"<script>const calls = {load: 'library.words', save: "words.add"};</script>"#), ["library.words", "words.add"])
        XCTAssertEqual(scan(#"<script>palabra.call( "ai.generate" , {})</script>"#), ["ai.generate"])
    }

    func testOnlyRegisteredNamesCount() {
        XCTAssertEqual(scan(#"<script>palabra.call("made.up"); var url = "example.com"; var v = "1.2.3";</script>"#), [])
        XCTAssertEqual(scan("<p>library.words in plain text is not a call</p>"), [], "unquoted text is not a use")
    }

    func testResultIsSortedAndUnique() {
        XCTAssertEqual(scan(#""words.add" "library.words" "words.add""#), ["library.words", "words.add"])
    }

    func testMergeKeepsWhatWasDeclaredAndAddsWhatThePageUses() {
        let html = #"<script>palabra.call("words.add")</script>"#
        XCTAssertEqual(ArtifactCapabilityScan.merged(declared: ["library.words"], html: html, registry: registry), ["library.words", "words.add"])
        XCTAssertEqual(ArtifactCapabilityScan.merged(declared: ["nope.nothing"], html: "<html></html>", registry: registry), [], "unknown declared names are dropped")
        XCTAssertEqual(ArtifactCapabilityScan.merged(declared: [], html: "", registry: registry), [])
    }

    // MARK: the whole path: import -> approval

    private func importPage(_ html: String) -> ArtifactDraft? {
        let generator = ArtifactGenerator(ai: MockAIClient(), registry: registry, allowedKinds: [.spec, .app])
        if case .success(let draft) = generator.importDraft(html, fixedTitle: nil, expectedKind: nil, userPrompt: "x") { return draft }
        return nil
    }

    func testAnImportedPageThatUsesACapabilityIndirectlyAsksForIt() throws {
        let draft = try XCTUnwrap(importPage(#"<html><head><title>T</title></head><body><script>const c = "words.add"; palabra.call(c, {})</script></body></html>"#))
        XCTAssertEqual(draft.requests, ["words.add"])
        let pending = ArtifactApproval.pending(kind: .app, requested: draft.requests, granted: [], registry: registry)
        XCTAssertEqual(pending.map(\.name), ["words.add"], "the person is asked before the app can write")
    }

    func testAnEnvelopeThatForgotToListWhatThePageUsesStillAsks() throws {
        let envelope = #"{"kind":"app","title":"T","requests":[]}"# + "\n---PAYLOAD---\n" + #"<html><body><script>palabra.call("library.words")</script></body></html>"# + "\n---END---"
        let draft = try XCTUnwrap(importPage(envelope))
        XCTAssertEqual(draft.requests, ["library.words"])
        XCTAssertEqual(ArtifactApproval.pending(kind: .app, requested: draft.requests, granted: [], registry: registry).map(\.name), ["library.words"])
    }

    func testApprovingMakesTheCallsWork() throws {
        let draft = try XCTUnwrap(importPage(#"<html><body><script>palabra.call("words.add")</script></body></html>"#))
        XCTAssertEqual(ArtifactApproval.effective(kind: .app, requested: draft.requests, granted: [], registry: registry), [], "nothing runs before approval")
        XCTAssertEqual(ArtifactApproval.effective(kind: .app, requested: draft.requests, granted: ["words.add"], registry: registry), ["words.add"])
    }

    func testOwnStorageNeverAsks() throws {
        let draft = try XCTUnwrap(importPage(#"<html><body><script>palabra.call("storage.get")</script></body></html>"#))
        XCTAssertTrue(ArtifactApproval.pending(kind: .app, requested: draft.requests, granted: [], registry: registry).isEmpty)
    }

    func testAPageThatUsesNothingAsksNothing() throws {
        let draft = try XCTUnwrap(importPage("<html><body>hola</body></html>"))
        XCTAssertEqual(draft.requests, [])
    }

    // MARK: apps saved before the page was read

    func testASavedAppIsAskedAboutWhatItsPageUsesEvenIfNothingWasSaved() {
        let html = Data(#"<html><script>palabra.call("words.add")</script></html>"#.utf8)
        XCTAssertEqual(ArtifactDetailView.requests(saved: [], kind: .app, payload: html, registry: registry), ["words.add"])
        XCTAssertEqual(ArtifactDetailView.requests(saved: ["library.words"], kind: .app, payload: html, registry: registry), ["library.words", "words.add"])
    }

    func testAPageArtifactIsNeverScanned() {
        let json = Data(#"{"blocks":[{"type":"text","text":"words.add"}]}"#.utf8)
        XCTAssertEqual(ArtifactDetailView.requests(saved: ["library.words"], kind: .spec, payload: json, registry: registry), ["library.words"])
    }
}
