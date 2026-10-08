import XCTest
@testable import Palabra

/// Keeps `StubAIClient`'s artifact envelope in sync with the real prompt, parser and validator.
final class StubArtifactTests: XCTestCase {
    private let model = AIModel(id: "models/stub", displayName: "Stub", description: nil, inputTokenLimit: 1_000_000, outputTokenLimit: 8192)
    private let registry = CapabilityRegistry([makeCapability("library.words", .read)])

    private func generator() -> ArtifactGenerator {
        ArtifactGenerator(ai: StubAIClient(), registry: registry)
    }

    func testStubCreateParsesThroughGenerator() async {
        let result = await generator().create(request: "a table of my words", apiKey: "k", model: model)
        guard case .success(let draft) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(draft.title, "Stub artifact")
        XCTAssertEqual(draft.requests, ["library.words"])
        let spec = try? JSONDecoder().decode(ArtifactSpec.self, from: draft.payload)
        XCTAssertEqual(spec?.blocks.count, 4)
    }

    func testStubUpdateAddsUpdatedBlock() async {
        let created = await generator().create(request: "a table of my words", apiKey: "k", model: model)
        guard case .success(let first) = created else { return XCTFail("create failed") }
        let updated = await generator().update(kind: .spec, currentTitle: first.title, currentPayload: first.payload, change: "add a note", apiKey: "k", model: model)
        guard case .success(let draft) = updated else { return XCTFail("expected success, got \(updated)") }
        let spec = try? JSONDecoder().decode(ArtifactSpec.self, from: draft.payload)
        XCTAssertEqual(spec?.blocks.count, 5)
        XCTAssertEqual(spec?.blocks.last, .text("Updated"))
    }

    func testStubFailurePath() async {
        let result = await generator().create(request: "fallo", apiKey: "k", model: model)
        XCTAssertEqual(result, .failure(.ai(.rateLimited)))
    }

    func testStubAppEnvelopeParsesThroughGenerator() async {
        let both = ArtifactGenerator(ai: StubAIClient(), registry: CapabilityRegistry([makeCapability("library.words", .read), makeCapability("storage.get", .local)]), allowedKinds: [.spec, .app])
        let result = await both.create(request: "build a practice app", apiKey: "k", model: model)
        guard case .success(let draft) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(draft.kind, .app)
        XCTAssertEqual(draft.title, "Stub app")
        XCTAssertEqual(draft.requests, ["library.words", "storage.get"])
        XCTAssertEqual(ArtifactHTMLLint.check(String(decoding: draft.payload, as: UTF8.self)), .success(String(decoding: draft.payload, as: UTF8.self)))
    }

    func testStubAppUpdateChangesTitleText() async {
        let both = ArtifactGenerator(ai: StubAIClient(), registry: CapabilityRegistry([makeCapability("library.words", .read), makeCapability("storage.get", .local)]), allowedKinds: [.spec, .app])
        let created = await both.create(request: "build a practice app", apiKey: "k", model: model)
        guard case .success(let first) = created else { return XCTFail("create failed") }
        let updated = await both.update(kind: .app, currentTitle: first.title, currentPayload: first.payload, change: "add a heading", apiKey: "k", model: model)
        guard case .success(let draft) = updated else { return XCTFail("expected success, got \(updated)") }
        XCTAssertTrue(String(decoding: draft.payload, as: UTF8.self).contains("Stub app updated"))
        XCTAssertEqual(draft.kind, .app)
    }
}
