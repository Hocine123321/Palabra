import XCTest
import SwiftData
@testable import Palabra

private struct RunCall: Sendable {
    let prompt: String
    let schema: JSONValue?
    let temperature: Double
}

private final class RunLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [RunCall] = []
    func add(_ call: RunCall) { lock.lock(); calls.append(call); lock.unlock() }
    var all: [RunCall] { lock.lock(); defer { lock.unlock() }; return calls }
}

@MainActor
final class AIGenerateCapabilityTests: XCTestCase {
    private var registry: CapabilityRegistry!
    private var gateway: AIGateway!
    private let log = RunLog()
    private let session = ArtifactSession(artifactID: UUID(), dryRun: false)

    override func setUp() {
        let container = try! ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let words = SwiftDataWordRepository(context: ModelContext(container))
        gateway = AIGateway()
        let log = self.log
        gateway.run = { prompt, schema, temperature in
            log.add(RunCall(prompt: prompt, schema: schema, temperature: temperature))
            return .success("respuesta")
        }
        registry = CapabilityProviders.registry(words: words, artifacts: SwiftDataArtifactRepository.inMemory(), aiGateway: gateway)
    }

    private func call(_ args: JSONValue, session: ArtifactSession? = nil, granted: Set<String> = ["ai.generate"]) async -> Result<JSONValue, CapabilityError> {
        await registry.call(name: "ai.generate", args: args, session: session ?? self.session, granted: granted)
    }

    private func prompt(_ text: String, extra: [String: JSONValue] = [:]) -> JSONValue {
        var object: [String: JSONValue] = ["prompt": .string(text)]
        object.merge(extra) { _, new in new }
        return .object(object)
    }

    func testReturnsText() async {
        let result = await call(prompt("di hola"))
        XCTAssertEqual(result, .success(.object(["text": .string("respuesta")])))
        XCTAssertEqual(log.all.map(\.prompt), ["di hola"])
    }

    func testPromptTooLongIsBadArgs() async {
        let tooLong = await call(prompt(String(repeating: "a", count: 8_001)))
        guard case .failure(.badArgs) = tooLong else { return XCTFail("expected badArgs, got \(tooLong)") }
        let exact = await call(prompt(String(repeating: "a", count: 8_000)))
        guard case .success = exact else { return XCTFail("exactly 8000 characters must pass") }
        XCTAssertEqual(log.all.count, 1)
    }

    func testMissingOrEmptyPromptIsBadArgs() async {
        let invalid: [JSONValue] = [.object([:]), prompt("   "), .object(["prompt": .number(3)]), .array([])]
        for args in invalid {
            let result = await call(args)
            guard case .failure(.badArgs) = result else { return XCTFail("expected badArgs for \(args)") }
        }
        XCTAssertTrue(log.all.isEmpty)
    }

    func testSchemaMustBeAnObject() async {
        let bad = await call(prompt("x", extra: ["schema": .string("nope")]))
        guard case .failure(.badArgs) = bad else { return XCTFail("expected badArgs") }
        let schema: JSONValue = .object(["type": .string("object")])
        _ = await call(prompt("x", extra: ["schema": schema]))
        XCTAssertEqual(log.all.last?.schema, schema)
    }

    func testTemperatureClampedAndDefaulted() async {
        _ = await call(prompt("a", extra: ["temperature": .number(9)]))
        _ = await call(prompt("b", extra: ["temperature": .number(-1)]))
        _ = await call(prompt("c"))
        XCTAssertEqual(log.all.map(\.temperature), [2.0, 0.0, 0.7])
        let bad = await call(prompt("d", extra: ["temperature": .string("hot")]))
        guard case .failure(.badArgs) = bad else { return XCTFail("expected badArgs") }
    }

    func testRateLimitedAfterTenCalls() async {
        for _ in 0..<10 {
            let ok = await call(prompt("x"))
            guard case .success = ok else { return XCTFail("first ten calls must pass") }
        }
        let eleventh = await call(prompt("x"))
        XCTAssertEqual(eleventh, .failure(.rateLimited))
        XCTAssertEqual(log.all.count, 10)
    }

    func testInvalidArgsDoNotSpendTheBudget() async {
        for _ in 0..<20 { _ = await call(.object([:])) }
        let result = await call(prompt("x"))
        guard case .success = result else { return XCTFail("bad calls must not count") }
    }

    func testEachSessionHasItsOwnBudget() async {
        for _ in 0..<10 { _ = await call(prompt("x")) }
        let other = ArtifactSession(artifactID: session.artifactID, dryRun: false)
        let result = await call(prompt("x"), session: other)
        guard case .success = result else { return XCTFail("a new session starts fresh") }
    }

    func testAIErrorMapsToFailedWithGuidance() async {
        gateway.run = { _, _, _ in .failure(.offline) }
        let result = await call(prompt("x"))
        XCTAssertEqual(result, .failure(.failed(AIError.offline.userMessage)))
    }

    func testNoGatewayFailsCleanly() async {
        gateway.run = nil
        let result = await call(prompt("x"))
        XCTAssertEqual(result, .failure(.failed("AI is not available")))
    }

    func testNotGrantedWithoutApproval() async {
        let result = await call(prompt("x"), granted: [])
        XCTAssertEqual(result, .failure(.notGranted))
        XCTAssertTrue(log.all.isEmpty)
    }

    func testManualListsAIGenerateForAppsOnly() {
        XCTAssertTrue(registry.manual().contains("ai.generate"))
        XCTAssertFalse(registry.manual(including: [.read]).contains("ai.generate"))
    }

    func testAIClassNeedsApprovalForApp() {
        let appPending = GrantPolicy.needingApproval(kind: .app, requested: ["ai.generate", "storage.get"], registry: registry)
        XCTAssertEqual(appPending.map(\.name), ["ai.generate"])
        // Specs cannot be granted `.ai`; pinned so a future change is deliberate.
        let specPending = GrantPolicy.needingApproval(kind: .spec, requested: ["ai.generate", "storage.get"], registry: registry)
        XCTAssertEqual(specPending.map(\.name), ["ai.generate"])
    }
}
