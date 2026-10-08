import XCTest
@testable import Palabra

/// Thread-safe counter for `onError` callbacks.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return messages.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return messages }
    func add(_ message: String) { lock.lock(); messages.append(message); lock.unlock() }
}

private final class GrantBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Set<String>
    init(_ value: Set<String>) { self.value = value }
    var current: Set<String> { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Set<String>) { lock.lock(); value = new; lock.unlock() }
}

final class BridgeDispatcherTests: XCTestCase {
    private let session = ArtifactSession(artifactID: UUID(), dryRun: false)
    private let errors = Counter()

    private func dispatcher(
        _ capabilities: [Capability],
        granted: Set<String> = ["library.words"],
        grantBox: GrantBox? = nil,
        timeout: @escaping @Sendable (String) -> TimeInterval = { _ in 5 }
    ) -> BridgeDispatcher {
        let errors = self.errors
        let box = grantBox ?? GrantBox(granted)
        return BridgeDispatcher(
            registry: CapabilityRegistry(capabilities),
            session: session,
            granted: { box.current },
            onError: { errors.add($0) },
            timeout: timeout
        )
    }

    private func body(_ name: String, args: JSONValue? = .object([:])) -> JSONValue {
        var object: [String: JSONValue] = ["name": .string(name)]
        if let args { object["args"] = args }
        return .object(object)
    }

    func testReadSucceeds() async {
        let d = dispatcher([makeCapability("library.words", .read, result: .array([.string("hola")]))])
        let reply = await d.handle(body: body("library.words"), byteCount: 40, isMainFrame: true)
        XCTAssertEqual(reply, .ok(.array([.string("hola")])))
        XCTAssertEqual(reply.json, .object(["ok": .bool(true), "value": .array([.string("hola")])]))
    }

    func testUnknownCapability() async {
        let d = dispatcher([])
        let reply = await d.handle(body: body("nope"), byteCount: 20, isMainFrame: true)
        guard case .error(let code, _) = reply else { return XCTFail("expected error") }
        XCTAssertEqual(code, "unknown")
    }

    func testUngrantedCapability() async {
        let box = CallBox()
        let d = dispatcher([makeCapability("review.flag", .write, box: box)], granted: [])
        let reply = await d.handle(body: body("review.flag"), byteCount: 20, isMainFrame: true)
        guard case .error(let code, _) = reply else { return XCTFail("expected error") }
        XCTAssertEqual(code, "notGranted")
        XCTAssertFalse(box.called)
    }

    func testBadShapeIsBadMessage() async {
        let d = dispatcher([makeCapability("library.words", .read)])
        let bodies: [JSONValue] = [
            .array([.string("library.words")]),
            .object(["args": .object([:])]),
            .object(["name": .number(3)]),
            .object(["name": .string("")]),
            .string("library.words"),
        ]
        for value in bodies {
            let reply = await d.handle(body: value, byteCount: 20, isMainFrame: true)
            guard case .error(let code, _) = reply else { return XCTFail("expected error for \(value)") }
            XCTAssertEqual(code, "badMessage")
        }
    }

    func testOversizedMessageNeverReachesTheHandler() async {
        let box = CallBox()
        let d = dispatcher([makeCapability("library.words", .read, box: box)])
        let reply = await d.handle(body: body("library.words"), byteCount: BridgeLimits.maxMessageBytes + 1, isMainFrame: true)
        guard case .error(let code, _) = reply else { return XCTFail("expected error") }
        XCTAssertEqual(code, "badMessage")
        XCTAssertFalse(box.called)
    }

    func testExactlyTheLimitIsAccepted() async {
        let d = dispatcher([makeCapability("library.words", .read)])
        let reply = await d.handle(body: body("library.words"), byteCount: BridgeLimits.maxMessageBytes, isMainFrame: true)
        guard case .ok = reply else { return XCTFail("expected ok") }
    }

    func testNonMainFrameIsRejected() async {
        let box = CallBox()
        let d = dispatcher([makeCapability("library.words", .read, box: box)])
        let reply = await d.handle(body: body("library.words"), byteCount: 20, isMainFrame: false)
        guard case .error(let code, _) = reply else { return XCTFail("expected error") }
        XCTAssertEqual(code, "badMessage")
        XCTAssertFalse(box.called)
    }

    func testMissingOrNullArgsAreAnEmptyObject() async {
        let seen = Counter()
        let capability = Capability(name: "library.words", kind: .read, summary: "s", returnsSummary: "r", handler: { args, _ in
            seen.add(args.jsonString)
            return .success(.null)
        })
        let d = dispatcher([capability])
        _ = await d.handle(body: body("library.words", args: nil), byteCount: 20, isMainFrame: true)
        _ = await d.handle(body: body("library.words", args: .null), byteCount: 20, isMainFrame: true)
        XCTAssertEqual(seen.all, ["{}", "{}"])
    }

    func testTimeoutReturnsTimeoutReply() async {
        let slow = Capability(name: "library.words", kind: .read, summary: "s", returnsSummary: "r", handler: { _, _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return .success(.null)
        })
        let d = dispatcher([slow], timeout: { _ in 0.05 })
        let reply = await d.handle(body: body("library.words"), byteCount: 20, isMainFrame: true)
        guard case .error(let code, _) = reply else { return XCTFail("expected error") }
        XCTAssertEqual(code, "timeout")
    }

    func testAIGenerateGetsTheLongerTimeout() {
        let d = BridgeDispatcher(registry: CapabilityRegistry([]), session: session, granted: { [] })
        XCTAssertEqual(d.timeout("ai.generate"), BridgeLimits.aiTimeout)
        XCTAssertEqual(d.timeout("library.words"), BridgeLimits.defaultTimeout)
        XCTAssertEqual(BridgeLimits.aiTimeout, 120)
        XCTAssertEqual(BridgeLimits.defaultTimeout, 30)
    }

    func testCapabilityErrorsMapToCodes() async {
        func failing(_ error: CapabilityError) -> Capability {
            Capability(name: "library.words", kind: .read, summary: "s", returnsSummary: "r", handler: { _, _ in .failure(error) })
        }
        let cases: [(CapabilityError, String)] = [
            (.badArgs("limit must be an integer"), "badArgs"),
            (.failed("storage full"), "failed"),
            (.rateLimited, "rateLimited"),
        ]
        for (error, expected) in cases {
            let reply = await dispatcher([failing(error)]).handle(body: body("library.words"), byteCount: 20, isMainFrame: true)
            guard case .error(let code, let message) = reply else { return XCTFail("expected error") }
            XCTAssertEqual(code, expected)
            XCTAssertFalse(message.isEmpty)
        }
        XCTAssertEqual(BridgeReply.error(code: "x", message: "y").json, .object(["ok": .bool(false), "error": .object(["code": .string("x"), "message": .string("y")])]))
    }

    func testErrorsAreReportedToTheLog() async {
        let d = dispatcher([])
        _ = await d.handle(body: body("nope"), byteCount: 20, isMainFrame: true)
        _ = await d.handle(body: .null, byteCount: 4, isMainFrame: true)
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.all[0].contains("nope"))
    }

    func testGrantIsReadOnEveryCall() async {
        let grants = GrantBox([])
        let d = dispatcher([makeCapability("library.words", .read)], grantBox: grants)
        let before = await d.handle(body: body("library.words"), byteCount: 20, isMainFrame: true)
        grants.set(["library.words"])
        let after = await d.handle(body: body("library.words"), byteCount: 20, isMainFrame: true)
        guard case .error = before, case .ok = after else { return XCTFail("grant change must apply to the next call") }
    }

    func testLocalNeedsNoGrant() async {
        let d = dispatcher([makeCapability("storage.get", .local, result: .string("v"))], granted: [])
        let reply = await d.handle(body: body("storage.get", args: .object(["key": .string("k")])), byteCount: 20, isMainFrame: true)
        XCTAssertEqual(reply, .ok(.string("v")))
    }

    // MARK: Foundation conversion (the web view's body and reply)

    func testFoundationRoundTrip() {
        let value: JSONValue = .object([
            "a": .null, "b": .bool(true), "c": .number(2.5), "d": .string("x"),
            "e": .array([.number(1), .bool(false)]), "f": .object(["g": .string("h")]),
        ])
        XCTAssertEqual(JSONValue.from(foundation: value.foundationObject), value)
    }

    func testBooleansAreNotNumbers() {
        let parsed = JSONValue.from(foundation: ["yes": NSNumber(value: true), "one": NSNumber(value: 1)] as [String: Any])
        XCTAssertEqual(parsed, .object(["yes": .bool(true), "one": .number(1)]))
    }

    func testNonJSONFoundationValuesAreRejected() {
        XCTAssertNil(JSONValue.from(foundation: Date()))
        XCTAssertNil(JSONValue.from(foundation: ["a": Date()] as [String: Any]))
        XCTAssertNil(JSONValue.from(foundation: [Date()] as [Any]))
    }
}
