import XCTest
@testable import Palabra

/// What the page may see of artifacts. The reader works through closures, so nothing here needs a database.
final class WebArtifactReaderTests: XCTestCase {
    private func read(_ name: String, _ value: JSONValue) -> Capability {
        Capability(name: name, kind: .read, summary: "", returnsSummary: "", handler: { _, _ in .success(value) })
    }

    private func reader(_ entries: [WebArtifactReader.Entry], payloads: [String: String], ticks: [String: Set<Int>] = [:],
                        capabilities: [Capability] = []) -> WebArtifactReader {
        WebArtifactReader(
            list: { entries },
            payload: { payloads[$0].map { Data($0.utf8) } },
            ticks: { id, block in ticks["\(id)/\(block)"] ?? [] },
            registry: CapabilityRegistry(capabilities)
        )
    }

    private func entry(_ id: String, _ title: String = "T", _ kind: ArtifactKind = .spec, at seconds: TimeInterval = 0) -> WebArtifactReader.Entry {
        .init(id: id, title: title, kind: kind, updatedAt: Date(timeIntervalSince1970: seconds))
    }

    private func object(_ value: JSONValue?) -> [String: JSONValue] {
        guard case .object(let o)? = value else { XCTFail("not an object: \(String(describing: value))"); return [:] }
        return o
    }

    func testTheListHasTitlesAndKindsNewestFirstAndNeverAPayload() async {
        let r = reader([entry("a", "Old", .spec, at: 1), entry("b", "New", .app, at: 9)], payloads: ["a": "SECRET", "b": "<script>"])
        guard case .array(let items) = await r.listPayload() else { return XCTFail("expected an array") }
        XCTAssertEqual(items.map { object($0)["title"]?.stringValue }, ["New", "Old"])
        XCTAssertEqual(object(items[0])["viewable"], .bool(false))     // an app is listed, not shown
        XCTAssertEqual(object(items[1])["viewable"], .bool(true))
        for item in items { XCTAssertTrue(Set(object(item).keys).isDisjoint(with: ["payload", "html", "spec"])) }
        XCTAssertFalse(items.map { $0.jsonString }.joined().contains("SECRET"))
    }

    func testASpecIsDecodedIntoPlainBlocks() async {
        let json = #"{"blocks":[{"type":"heading","level":2,"text":"Plan"},{"type":"text","text":"Hola"},{"type":"list","ordered":true,"items":["a","b"]}]}"#
        let page = await reader([entry("s", "My plan")], payloads: ["s": json]).page(id: "s")
        let o = object(page)
        XCTAssertEqual(o["title"], .string("My plan"))
        guard case .array(let blocks)? = o["blocks"] else { return XCTFail("no blocks") }
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(object(blocks[0])["type"], .string("heading"))
        XCTAssertEqual(object(blocks[2])["ordered"], .bool(true))
    }

    func testAnAppIsNeverSentEvenIfAskedForByItsId() async {
        let r = reader([entry("x", "Game", .app)], payloads: ["x": "<html><script>steal()</script></html>"])
        let page = await r.page(id: "x")
        XCTAssertNil(page)
    }

    func testUnknownIdsAndBrokenPayloadsGiveNothing() async {
        let r = reader([entry("ok"), entry("bad")], payloads: ["bad": "not json"])
        let unknown = await r.page(id: "nope")
        let noPayload = await r.page(id: "ok")
        let broken = await r.page(id: "bad")
        XCTAssertNil(unknown); XCTAssertNil(noPayload); XCTAssertNil(broken)
    }

    func testABoundTableIsResolvedOnThePhoneFromAReadTheWebMayMake() async {
        let words: JSONValue = .array([.object(["spanish": .string("hola"), "translation": .string("hello")])])
        let json = #"{"blocks":[{"type":"table","columns":[{"title":"Word","field":"spanish"},{"title":"Meaning","field":"translation"}],"bind":{"capability":"library.words","args":{}}}]}"#
        let page = await reader([entry("t")], payloads: ["t": json], capabilities: [read("library.words", words)]).page(id: "t")
        guard case .array(let blocks)? = object(page)["blocks"] else { return XCTFail("no blocks") }
        let table = object(blocks[0])
        XCTAssertEqual(table["type"], .string("table"))
        XCTAssertEqual(table["rows"], .array([.array([.string("hola"), .string("hello")])]))
    }

    func testABindToAReadTheWebMayNotMakeShowsAnInlineNoteAndRunsNothing() async {
        let ran = Box(false)
        let secret = Capability(name: "storage.get", kind: .read, summary: "", returnsSummary: "", handler: { _, _ in ran.value = true; return .success(.array([])) })
        let json = #"{"blocks":[{"type":"table","columns":[{"title":"X"}],"bind":{"capability":"storage.get","args":{}}}]}"#
        let page = await reader([entry("t")], payloads: ["t": json], capabilities: [secret]).page(id: "t")
        guard case .array(let blocks)? = object(page)["blocks"] else { return XCTFail("no blocks") }
        XCTAssertEqual(object(blocks[0])["type"], .string("note"))
        XCTAssertFalse(ran.value)
    }

    func testABindToAWriteIsNotRun() async {
        let ran = Box(false)
        let write = Capability(name: "words.add", kind: .write, summary: "", returnsSummary: "", dryRunValue: .object([:]), handler: { _, _ in ran.value = true; return .success(.array([])) })
        let json = #"{"blocks":[{"type":"chart","style":"bar","bind":{"capability":"words.add","args":{}},"labelField":"a","valueField":"b"}]}"#
        _ = await reader([entry("t")], payloads: ["t": json], capabilities: [write]).page(id: "t")
        XCTAssertFalse(ran.value)
    }

    func testTicksAreShownForChecklistsAndRoadmaps() async {
        let json = #"{"blocks":[{"type":"checklist","id":"c","items":["a","b"]},{"type":"roadmap","id":"r","steps":[{"title":"One"},{"title":"Two","detail":"d"}]}]}"#
        let page = await reader([entry("p")], payloads: ["p": json], ticks: ["p/c": [1], "p/r": [0]]).page(id: "p")
        guard case .array(let blocks)? = object(page)["blocks"] else { return XCTFail("no blocks") }
        guard case .array(let items)? = object(blocks[0])["items"], case .array(let steps)? = object(blocks[1])["steps"] else { return XCTFail("shape") }
        XCTAssertEqual(items.map { object($0)["done"] }, [.bool(false), .bool(true)])
        XCTAssertEqual(steps.map { object($0)["done"] }, [.bool(true), .bool(false)])
    }

    func testDispatcherAnswersListAndPageAndRefusesWhatItCannotShow() async {
        let r = reader([entry("s"), entry("g", "Game", .app)], payloads: ["s": #"{"blocks":[{"type":"text","text":"hi"}]}"#, "g": "<html>"])
        let d = WebLinkDispatcher(registry: CapabilityRegistry([]), artifacts: r)
        let list = await d.handle(LinkMessage(id: "1", type: "artifacts", version: 1, payload: nil))
        XCTAssertEqual(list?.type, "ack")
        let page = await d.handle(LinkMessage(id: "2", type: "artifact", version: 1, payload: .object(["id": .string("s")])))
        XCTAssertEqual(page?.type, "ack")
        let refused: [JSONValue] = [.object(["id": .string("g")]), .object(["id": .string("zzz")])]
        for payload in refused {
            let reply = await d.handle(LinkMessage(id: "3", type: "artifact", version: 1, payload: payload))
            XCTAssertEqual(reply?.payload, .object(["reason": .string("not-found")]))
        }
        let bad = await d.handle(LinkMessage(id: "4", type: "artifact", version: 1, payload: .object([:])))
        XCTAssertEqual(bad?.payload, .object(["reason": .string("bad-request")]))
        let none = await WebLinkDispatcher(registry: CapabilityRegistry([])).handle(LinkMessage(id: "5", type: "artifacts", version: 1, payload: nil))
        XCTAssertEqual(none?.payload, .object(["result": .array([])]))
    }
}
