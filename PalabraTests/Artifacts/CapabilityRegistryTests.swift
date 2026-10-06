import XCTest
@testable import Palabra

/// Records whether a handler ran, safely across concurrency domains.
final class CallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var called: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func mark() { lock.lock(); flag = true; lock.unlock() }
}

func makeCapability(
    _ name: String,
    _ kind: CapabilityClass,
    box: CallBox = CallBox(),
    result: JSONValue = .object([:]),
    dryRun: JSONValue? = nil
) -> Capability {
    Capability(
        name: name,
        kind: kind,
        summary: "summary of \(name)",
        argsSchema: .object(["limit": .string("max items")]),
        returnsSummary: "returns of \(name)",
        dryRunValue: dryRun,
        handler: { _, _ in
            box.mark()
            return .success(result)
        }
    )
}

final class CapabilityRegistryTests: XCTestCase {
    private let session = ArtifactSession(artifactID: UUID(), dryRun: false)
    private let dryRunSession = ArtifactSession(artifactID: nil, dryRun: true)

    func testUnknownName() async {
        let registry = CapabilityRegistry([makeCapability("library.words", .read)])
        let result = await registry.call(name: "nope", args: .object([:]), session: session, granted: ["nope"])
        XCTAssertEqual(result, .failure(.unknown))
    }

    func testUngrantedReadIsNotGranted() async {
        let box = CallBox()
        let registry = CapabilityRegistry([makeCapability("library.words", .read, box: box)])
        let result = await registry.call(name: "library.words", args: .object([:]), session: session, granted: [])
        XCTAssertEqual(result, .failure(.notGranted))
        XCTAssertFalse(box.called)
    }

    func testLocalIsAlwaysGranted() async {
        let registry = CapabilityRegistry([makeCapability("storage.get", .local)])
        let result = await registry.call(name: "storage.get", args: .object([:]), session: session, granted: [])
        XCTAssertEqual(result, .success(.object([:])))
    }

    func testOversizedArgsAreBadArgs() async {
        let box = CallBox()
        let registry = CapabilityRegistry([makeCapability("storage.set", .local, box: box)])
        let big = JSONValue.object(["v": .string(String(repeating: "a", count: 65_537))])
        let result = await registry.call(name: "storage.set", args: big, session: session, granted: [])
        guard case .failure(.badArgs) = result else { return XCTFail("expected badArgs, got \(result)") }
        XCTAssertFalse(box.called)
    }

    func testDryRunWriteReturnsDryRunValueWithoutRunningHandler() async {
        let box = CallBox()
        let registry = CapabilityRegistry([makeCapability("review.flag", .write, box: box, dryRun: .string("ok"))])
        let result = await registry.call(name: "review.flag", args: .object([:]), session: dryRunSession, granted: ["review.flag"])
        XCTAssertEqual(result, .success(.string("ok")))
        XCTAssertFalse(box.called)
    }

    func testDryRunStillRunsReads() async {
        let box = CallBox()
        let registry = CapabilityRegistry([makeCapability("library.words", .read, box: box)])
        _ = await registry.call(name: "library.words", args: .object([:]), session: dryRunSession, granted: ["library.words"])
        XCTAssertTrue(box.called)
    }

    func testRealWriteRunsHandler() async {
        let box = CallBox()
        let registry = CapabilityRegistry([makeCapability("review.flag", .write, box: box, result: .string("done"), dryRun: .string("ok"))])
        let result = await registry.call(name: "review.flag", args: .object([:]), session: session, granted: ["review.flag"])
        XCTAssertEqual(result, .success(.string("done")))
        XCTAssertTrue(box.called)
    }

    func testLaterDuplicateReplacesEarlier() async {
        let registry = CapabilityRegistry([
            makeCapability("a", .read, result: .string("first")),
            makeCapability("a", .read, result: .string("second")),
        ])
        let result = await registry.call(name: "a", args: .object([:]), session: session, granted: ["a"])
        XCTAssertEqual(result, .success(.string("second")))
        XCTAssertEqual(registry.all.count, 1)
    }

    func testManualListsEveryCapabilityAndHonoursClasses() {
        let registry = CapabilityRegistry([
            makeCapability("library.words", .read),
            makeCapability("review.flag", .write),
        ])
        let all = registry.manual()
        XCTAssertTrue(all.contains("library.words"))
        XCTAssertTrue(all.contains("review.flag"))
        XCTAssertTrue(all.contains("summary of library.words"))
        XCTAssertTrue(all.contains(#"{"limit":"max items"}"#))
        XCTAssertTrue(all.contains("returns of library.words"))
        let readOnly = registry.manual(including: [.read])
        XCTAssertTrue(readOnly.contains("library.words"))
        XCTAssertFalse(readOnly.contains("review.flag"))
    }

    func testAllIsSortedByName() {
        let registry = CapabilityRegistry([makeCapability("b", .read), makeCapability("a", .read)])
        XCTAssertEqual(registry.all.map(\.name), ["a", "b"])
    }
}
