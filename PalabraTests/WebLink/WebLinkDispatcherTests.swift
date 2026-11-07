import XCTest
@testable import Palabra

final class WebLinkDispatcherTests: XCTestCase {
    private func read(_ name: String, value: JSONValue = .array([.string(name)])) -> Capability {
        Capability(name: name, kind: .read, summary: "", returnsSummary: "", handler: { _, _ in .success(value) })
    }

    private func write(_ name: String, ran: Box<Bool>) -> Capability {
        Capability(name: name, kind: .write, summary: "", returnsSummary: "", dryRunValue: .object([:]),
                   handler: { _, _ in ran.value = true; return .success(.object([:])) })
    }

    private func dispatcher(_ capabilities: [Capability]) -> WebLinkDispatcher {
        WebLinkDispatcher(registry: CapabilityRegistry(capabilities), now: { Date(timeIntervalSince1970: 0) })
    }

    private func request(_ type: String, _ payload: JSONValue?) -> LinkMessage { LinkMessage(id: "r1", type: type, version: 1, payload: payload) }

    private var allReads: [Capability] { WebLinkDispatcher.readAllowList.map { read($0) } }

    func testAReadOnTheAllowListIsAnswered() async throws {
        let reply = await dispatcher(allReads).handle(request("read", .object(["capability": .string("library.words"), "args": .object([:])])))
        XCTAssertEqual(reply?.type, "ack")
        XCTAssertEqual(reply?.id, "r1")
        XCTAssertEqual(reply?.payload, .object(["result": .array([.string("library.words")])]))
    }

    func testWritesAiAndStorageAreForbiddenAndNeverRun() async {
        let ran = Box(false)
        let d = dispatcher(allReads + [write("words.add", ran: ran), read("ai.generate"), read("storage.get"), write("study.addCards", ran: ran)])
        for name in ["words.add", "ai.generate", "storage.get", "study.addCards", "nope"] {
            let reply = await d.handle(request("read", .object(["capability": .string(name)])))
            XCTAssertEqual(reply?.type, "reject", name)
            XCTAssertEqual(reply?.payload, .object(["reason": .string("forbidden")]), name)
        }
        XCTAssertFalse(ran.value)
    }

    func testANameOnTheAllowListThatTheRegistryCallsAWriteIsStillRefused() async {
        let ran = Box(false)
        let d = dispatcher([write("library.words", ran: ran)])
        let reply = await d.handle(request("read", .object(["capability": .string("library.words")])))
        XCTAssertEqual(reply?.payload, .object(["reason": .string("forbidden")]))
        XCTAssertFalse(ran.value)
    }

    func testBadRequestsAreRejectedAndUnknownTypesIgnored() async {
        let d = dispatcher(allReads)
        let missing = await d.handle(request("read", nil))
        XCTAssertEqual(missing?.payload, .object(["reason": .string("bad-request")]))
        let notObject = await d.handle(request("read", .string("library.words")))
        XCTAssertEqual(notObject?.type, "reject")
        let unknown = await d.handle(request("hologram", nil))
        XCTAssertNil(unknown)
    }

    func testCapabilityFailuresBecomeShortReasons() async {
        let bad = Capability(name: "library.words", kind: .read, summary: "", returnsSummary: "", handler: { _, _ in .failure(.badArgs("x")) })
        let reply = await dispatcher([bad]).handle(request("read", .object(["capability": .string("library.words")])))
        XCTAssertEqual(reply?.payload, .object(["reason": .string("bad-args")]))
    }

    func testSnapshotCollectsEveryReadAndIsStamped() async throws {
        let reply = await dispatcher(allReads).handle(request("snapshot", nil))
        XCTAssertEqual(reply?.type, "ack")
        guard case .object(let payload)? = reply?.payload, case .object(let snapshot)? = payload["snapshot"] else { return XCTFail("no snapshot") }
        XCTAssertEqual(Set(snapshot.keys), Set(WebLinkDispatcher.snapshotReads.map(\.key)))
        XCTAssertEqual(payload["takenAt"], .string("1970-01-01T00:00:00Z"))
    }

    func testASnapshotThatCannotBeCompleteIsRejectedNotHalfSent() async {
        let missingStats = allReads.filter { $0.name != "stats.wordsPerWeek" }
        let reply = await dispatcher(missingStats).handle(request("snapshot", nil))
        XCTAssertEqual(reply?.type, "reject")
    }

    func testSnapshotReadsAreAllOnTheAllowList() {
        for read in WebLinkDispatcher.snapshotReads { XCTAssertTrue(WebLinkDispatcher.readAllowList.contains(read.capability), read.capability) }
    }
}

final class LinkChunkingTests: XCTestCase {
    private func big(_ bytes: Int) -> LinkMessage {
        LinkMessage(id: "c1", type: "ack", version: 1, payload: .object(["text": .string(String(repeating: "á", count: bytes / 2))]))
    }

    func testASmallReplyIsOnePieceAsItIs() throws {
        let reply = LinkMessage(id: "s", type: "ack", version: 1, payload: .object(["a": .number(1)]))
        XCTAssertEqual(try LinkChunking.pieces(of: reply), [reply])
    }

    func testABigReplyIsSplitAndPutsBackTogether() throws {
        let reply = big(500_000)
        let pieces = try LinkChunking.pieces(of: reply)
        XCTAssertGreaterThan(pieces.count, 3)
        XCTAssertTrue(pieces.allSatisfy { $0.type == "chunk" && $0.id == "c1" })
        for piece in pieces {   // each sealed frame must fit the relay's 256 KB
            XCTAssertLessThan(try JSONEncoder().encode(piece).count + 28, 256 * 1024)
        }
        XCTAssertEqual(try LinkChunking.reassemble(pieces.shuffled()), reply)
    }

    func testAMissingPieceIsAnErrorNotASilentTruncation() throws {
        var pieces = try LinkChunking.pieces(of: big(500_000))
        pieces.removeLast()
        XCTAssertThrowsError(try LinkChunking.reassemble(pieces))
    }
}
