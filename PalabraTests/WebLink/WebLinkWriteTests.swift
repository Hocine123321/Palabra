import XCTest
@testable import Palabra

/// Phase 4: what the phone does with a change or AI request from the page. The page can be tampered with; these are
/// the checks that matter, because the phone is where they are enforced.
final class WebLinkWriteTests: XCTestCase {
    private func counting(_ name: String, kind: CapabilityClass, runs: Box<Int>, result: JSONValue = .object(["ok": .bool(true)])) -> Capability {
        Capability(name: name, kind: kind, summary: "", returnsSummary: "", dryRunValue: kind == .write ? .object([:]) : nil,
                   handler: { _, _ in runs.value += 1; return .success(result) })
    }

    private func dispatcher(_ capabilities: [Capability], recent: RecentActions = RecentActions(),
                            live: [String: (String?, [String])] = [:]) -> WebLinkDispatcher {
        WebLinkDispatcher(registry: CapabilityRegistry(capabilities), now: { Date(timeIntervalSince1970: 0) }, recent: recent,
                          placement: { ref in live[ref].map { (category: $0.0, tags: $0.1) } })
    }

    private func write(_ id: String, _ capability: String, args: JSONValue = .object([:]), base: JSONValue? = nil) -> LinkMessage {
        var payload: [String: JSONValue] = ["id": .string(id), "capability": .string(capability), "args": args]
        if let base { payload["base"] = base }
        return LinkMessage(id: "r-\(id)", type: "write", version: 1, payload: .object(payload))
    }

    private func reason(_ reply: LinkMessage?) -> String? {
        guard reply?.type == "reject", case .object(let o)? = reply?.payload else { return nil }
        return o["reason"]?.stringValue
    }

    func testAllowedWritesRunOnceAndAreAcknowledged() async {
        for name in ["words.add", "words.place", "review.flag"] {
            let runs = Box(0)
            let reply = await dispatcher([counting(name, kind: .write, runs: runs)]).handle(write("a1", name))
            XCTAssertEqual(reply?.type, "ack", name)
            XCTAssertEqual(runs.value, 1, name)
        }
    }

    func testEverythingElseIsForbiddenAndNeverRuns() async {
        let runs = Box(0)
        let names = ["storage.set", "storage.remove", "words.delete", "study.addCards", "ai.generate", "settings.apiKey", "nope"]
        let d = dispatcher(names.map { counting($0, kind: .write, runs: runs) })
        for name in names {
            let awaited1 = await d.handle(write("x-\(name)", name))
            XCTAssertEqual(reason(awaited1), "forbidden", name)
        }
        XCTAssertEqual(runs.value, 0)
    }

    func testANameOnTheWriteListThatTheRegistryCallsAReadIsStillRefused() async {
        let runs = Box(0)
        let awaited2 = await dispatcher([counting("words.add", kind: .read, runs: runs)]).handle(write("a1", "words.add"))
        XCTAssertEqual(reason(awaited2), "forbidden")
        XCTAssertEqual(runs.value, 0)
    }

    func testARetryAfterALostReplyIsAnsweredWithTheFirstResultAndDoesNotActTwice() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.add", kind: .write, runs: runs, result: .object(["queued": .number(2)]))])
        let first = await d.handle(write("same", "words.add"))
        let again = await d.handle(write("same", "words.add"))
        XCTAssertEqual(runs.value, 1)
        XCTAssertEqual(again?.type, "ack")
        guard case .object(let a)? = first?.payload, case .object(let b)? = again?.payload else { return XCTFail("expected objects") }
        XCTAssertEqual(a["result"], b["result"])
        XCTAssertEqual(b["repeat"], .bool(true))
    }

    func testARefusedActionIsNotRememberedSoItCanBeRetried() async {
        let runs = Box(0)
        let failing = Capability(name: "words.add", kind: .write, summary: "", returnsSummary: "", dryRunValue: .object([:]),
                                 handler: { _, _ in runs.value += 1; return .failure(.failed("no")) })
        let d = dispatcher([failing])
        let awaited3 = await d.handle(write("r", "words.add"))
        XCTAssertEqual(reason(awaited3), "failed")
        let awaited4 = await d.handle(write("r", "words.add"))
        XCTAssertEqual(reason(awaited4), "failed")
        XCTAssertEqual(runs.value, 2)
    }

    func testMalformedWritesAreBadRequests() async {
        let d = dispatcher([counting("words.add", kind: .write, runs: Box(0))])
        let payloads: [JSONValue?] = [nil, .string("x"), .object([:]), .object(["capability": .string("words.add")]), .object(["id": .string(""), "capability": .string("words.add")]),
                                    .object(["id": .string(String(repeating: "a", count: 81)), "capability": .string("words.add")])]
        for payload in payloads {
            let awaited5 = await d.handle(LinkMessage(id: "m", type: "write", version: 1, payload: payload))
            XCTAssertEqual(reason(awaited5), "bad-request")
        }
    }

    func testAPlacementChangedOnThePhoneIsAConflictAndNothingRuns() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.place", kind: .write, runs: runs)], live: ["hola": ("Food", ["a"])])
        let args: JSONValue = .object(["words": .array([.object(["key": .string("hola"), "category": .string("Travel")])])])
        let stale: JSONValue = .object(["hola": .string(PlacementToken.make(category: "Greetings", tags: ["a"]))])
        let awaited6 = await d.handle(write("p1", "words.place", args: args, base: stale))
        XCTAssertEqual(reason(awaited6), "conflict")
        XCTAssertEqual(runs.value, 0)
    }

    func testAPlacementThatStillMatchesRuns() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.place", kind: .write, runs: runs)], live: ["hola": ("Food", ["b", "a"])])
        let args: JSONValue = .object(["words": .array([.object(["key": .string("hola"), "category": .string("Travel")])])])
        let current: JSONValue = .object(["hola": .string(PlacementToken.make(category: "Food", tags: ["a", "b"]))])
        let awaited7 = await d.handle(write("p1", "words.place", args: args, base: current))?.type
        XCTAssertEqual(awaited7, "ack")
        XCTAssertEqual(runs.value, 1)
    }

    func testAWordThatIsGoneIsNotFoundAndNothingRuns() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.place", kind: .write, runs: runs)], live: [:])
        let args: JSONValue = .object(["words": .array([.object(["key": .string("gone")])])])
        let awaited8 = await d.handle(write("p1", "words.place", args: args, base: .object(["gone": .string("|")])))
        XCTAssertEqual(reason(awaited8), "not-found")
        XCTAssertEqual(runs.value, 0)
    }

    func testOneStaleWordRefusesTheWholeActionNothingIsHalfApplied() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.place", kind: .write, runs: runs)], live: ["a": ("X", []), "b": ("Changed", [])])
        let args: JSONValue = .object(["words": .array([.object(["key": .string("a")]), .object(["key": .string("b")])])])
        let base: JSONValue = .object(["a": .string(PlacementToken.make(category: "X", tags: [])), "b": .string(PlacementToken.make(category: "Old", tags: []))])
        let awaited9 = await d.handle(write("p1", "words.place", args: args, base: base))
        XCTAssertEqual(reason(awaited9), "conflict")
        XCTAssertEqual(runs.value, 0)
    }

    func testRetryingAnywayWithoutABaseSkipsTheConflictCheck() async {
        let runs = Box(0)
        let d = dispatcher([counting("words.place", kind: .write, runs: runs)], live: ["a": ("Changed", [])])
        let args: JSONValue = .object(["words": .array([.object(["key": .string("a"), "category": .string("Mine")])])])
        let awaited10 = await d.handle(write("p1", "words.place", args: args, base: nil))?.type
        XCTAssertEqual(awaited10, "ack")
        XCTAssertEqual(runs.value, 1)
    }

    func testAiRunsOnlyThroughTheAiMessageAndOnlyForGenerate() async {
        let runs = Box(0)
        let d = dispatcher([counting("ai.generate", kind: .ai, runs: runs, result: .object(["text": .string("hola")]))])
        let reply = await d.handle(LinkMessage(id: "q", type: "ai", version: 1, payload: .object(["args": .object(["prompt": .string("x")])])))
        XCTAssertEqual(reply?.type, "ack")
        XCTAssertEqual(runs.value, 1)
        let awaited11 = await d.handle(write("w", "ai.generate"))
        XCTAssertEqual(reason(awaited11), "forbidden", "AI through the write path is refused")
        XCTAssertEqual(runs.value, 1)
    }

    func testAiIsRefusedWhenTheRegistryDoesNotCallItAi() async {
        let runs = Box(0)
        let d = dispatcher([counting("ai.generate", kind: .read, runs: runs)])
        let awaited12 = await d.handle(LinkMessage(id: "q", type: "ai", version: 1, payload: .object([:])))
        XCTAssertEqual(reason(awaited12), "forbidden")
        XCTAssertEqual(runs.value, 0)
    }

    func testTheMemoryOfRecentActionsIsBounded() {
        let recent = RecentActions(limit: 3)
        for i in 0..<5 { recent.remember(id: "a\(i)", reply: .number(Double(i))) }
        XCTAssertNil(recent.reply(for: "a0")); XCTAssertNil(recent.reply(for: "a1"))
        XCTAssertEqual(recent.reply(for: "a4"), .number(4))
    }
}
