import XCTest
@testable import Palabra

final class MirrorPusherTests: XCTestCase {
    private var directory: URL!
    private var vectors: MirrorVectors!
    private let origin = URL(string: "https://x.test")!

    override func setUpWithError() throws {
        vectors = try MirrorVectors.load()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-pusher-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: Fixtures

    private func secrets() -> MirrorSecrets {
        MirrorSecrets(
            origin: "https://x.test", mirrorID: "MIR", ownerDeviceID: "own", ownerToken: "tok",
            dataKey: Base64URL.encode(Data(hex: vectors.dataKeyHex)), computers: []
        )
    }

    private func keys() throws -> MirrorKeys { try XCTUnwrap(MirrorKeys(dataKey: Data(hex: vectors.dataKeyHex))) }

    private func makeIndex() -> MirrorIndex { MirrorIndex(fileURL: directory.appendingPathComponent("index.json")) }

    private func makePusher(_ index: MirrorIndex) -> MirrorPusher {
        MirrorPusher(client: MirrorClient(origin: origin, session: MockURLProtocol.session()), secrets: secrets(), index: index)
    }

    private func record(_ n: Int, kind: String = "word", text: String? = nil) -> MirrorRecord {
        MirrorRecord(kind: kind, recordID: "rec-\(n)", payload: .object(["spanish": .string(text ?? "palabra \(n)"), "n": .number(Double(n))]))
    }

    /// Accepts every PUT, counting the sequence like the Worker; `failOn` makes that numbered PUT answer with an error.
    private func server(failOn: (put: Int, status: Int)? = nil) -> (requests: Box<[URLRequest]>, puts: Box<Int>) {
        let requests = Box<[URLRequest]>([])
        let puts = Box<Int>(0)
        let seq = Box<Int>(0)
        MockURLProtocol.handler = { request in
            requests.value.append(request)
            puts.value += 1
            if let failOn, failOn.put == puts.value { return (failOn.status, Data(#"{"error":"boom"}"#.utf8)) }
            let items = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])?["items"] as? [[String: Any]]
            seq.value += items?.count ?? 0
            return (200, Data(#"{"seq":\#(seq.value)}"#.utf8))
        }
        return (requests, puts)
    }

    private func items(_ request: URLRequest) throws -> [[String: Any]] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        return try XCTUnwrap(body["items"] as? [[String: Any]])
    }

    private func open(_ item: [String: Any]) throws -> [String: Any] {
        let sealed = try XCTUnwrap(Base64URL.decode(try XCTUnwrap(item["sealed"] as? String)))
        let plain = try MirrorCrypto.openItem(keys: try keys(), itemID: try XCTUnwrap(item["id"] as? String), sealed: sealed)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
    }

    // MARK: Tests

    func testThreeNewRecordsAreSealedIntoOneRequest() async throws {
        let (requests, _) = server()
        let records = [record(1), record(2), record(3)]
        let result = try await makePusher(makeIndex()).push(records, kinds: ["word"])
        XCTAssertEqual(result, MirrorPushResult(sent: 3, deleted: 0, skipped: [], seq: 3))
        let request = try XCTUnwrap(requests.value.first)
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/m/MIR/items")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer own.tok")
        let sent = try items(request)
        XCTAssertEqual(sent.count, 3)
        for (item, source) in zip(sent, records) {
            XCTAssertEqual(item["id"] as? String, MirrorCrypto.itemID(keys: try keys(), kind: "word", recordID: source.recordID))
            let envelope = try open(item)
            XCTAssertEqual(envelope["v"] as? Int, 1)
            XCTAssertEqual(envelope["k"] as? String, "word")
            XCTAssertEqual(envelope["r"] as? String, source.recordID)
            XCTAssertEqual(envelope["g"] as? Int, 1)
            XCTAssertEqual(envelope["h"] as? String, source.contentHash)
            let payload = try XCTUnwrap(envelope["d"] as? [String: Any])
            XCTAssertEqual(payload["spanish"] as? String, source.payload["spanish"]?.stringValue)
            XCTAssertEqual(payload["n"] as? Int, source.payload["n"]?.intValue)
        }
    }

    func testNothingChangedSendsNothing() async throws {
        let (requests, _) = server()
        let index = makeIndex()
        let records = [record(1), record(2)]
        _ = try await makePusher(index).push(records, kinds: ["word"])
        requests.value = []
        let again = try await makePusher(index).push(records, kinds: ["word"])
        XCTAssertEqual(again, MirrorPushResult(sent: 0, deleted: 0, skipped: [], seq: nil))
        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertEqual(index.generation, 1, "an empty push does not bump the generation")
    }

    func testAChangedRecordIsTheOnlyOneResentWithTheNextGeneration() async throws {
        let (requests, _) = server()
        let index = makeIndex()
        _ = try await makePusher(index).push([record(1), record(2)], kinds: ["word"])
        requests.value = []
        _ = try await makePusher(index).push([record(1), record(2, text: "changed")], kinds: ["word"])
        let sent = try items(try XCTUnwrap(requests.value.first))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["id"] as? String, MirrorCrypto.itemID(keys: try keys(), kind: "word", recordID: "rec-2"))
        XCTAssertEqual(try open(sent[0])["g"] as? Int, 2)
    }

    func testARemovedRecordBecomesATombstoneAndLeavesTheIndex() async throws {
        let (requests, _) = server()
        let index = makeIndex()
        _ = try await makePusher(index).push([record(1), record(2)], kinds: ["word"])
        requests.value = []
        let result = try await makePusher(index).push([record(1)], kinds: ["word"])
        XCTAssertEqual(result.deleted, 1)
        let sent = try items(try XCTUnwrap(requests.value.first))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["deleted"] as? Bool, true)
        XCTAssertEqual(sent[0]["sealed"] as? String, "")
        let id = MirrorCrypto.itemID(keys: try keys(), kind: "word", recordID: "rec-2")
        XCTAssertNil(index.hash(of: id))
    }

    func testOtherKindsInTheIndexAreLeftAlone() async throws {
        let (requests, _) = server()
        let index = makeIndex()
        index.record(itemID: "deck-item", kind: "deck", hash: "x")
        _ = try await makePusher(index).push([record(1)], kinds: ["word"])
        XCTAssertEqual(try items(try XCTUnwrap(requests.value.first)).count, 1, "no tombstone for the deck")
        XCTAssertEqual(index.hash(of: "deck-item"), "x")
    }

    func test450RecordsGoOutInBatchesOf200() async throws {
        let (requests, _) = server()
        let result = try await makePusher(makeIndex()).push((1...450).map { record($0) }, kinds: ["word"])
        XCTAssertEqual(requests.value.map { (try? items($0).count) ?? -1 }, [200, 200, 50])
        XCTAssertEqual(result.sent, 450)
        XCTAssertEqual(result.seq, 450)
    }

    func testAnOversizedRecordIsSkippedAndItsNeighboursStillGo() async throws {
        let (requests, _) = server()
        let index = makeIndex()
        let huge = record(2, text: String(repeating: "x", count: 250_000))
        let result = try await makePusher(index).push([record(1), huge, record(3)], kinds: ["word"])
        XCTAssertEqual(result.skipped, ["rec-2"])
        XCTAssertEqual(result.sent, 2)
        XCTAssertEqual(try items(try XCTUnwrap(requests.value.first)).count, 2)
        XCTAssertNil(index.hash(of: MirrorCrypto.itemID(keys: try keys(), kind: "word", recordID: "rec-2")))
    }

    func testARateLimitMidwayKeepsTheFirstBatchAndARetrySendsTheRest() async throws {
        let index = makeIndex()
        let records = (1...450).map { record($0) }
        _ = server(failOn: (put: 2, status: 429))
        do {
            _ = try await makePusher(index).push(records, kinds: ["word"])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .http(status: 429, code: "boom"))
        }
        XCTAssertEqual(MirrorIndex(fileURL: directory.appendingPathComponent("index.json")).itemIDs(ofKind: "word").count, 200, "the first batch is on disk")

        let (requests, _) = server()
        let result = try await makePusher(index).push(records, kinds: ["word"])
        XCTAssertEqual(result.sent, 250)
        XCTAssertEqual(requests.value.map { (try? items($0).count) ?? -1 }, [200, 50])
    }

    func testAnUnauthorizedPushIndexesNothing() async throws {
        _ = server(failOn: (put: 1, status: 401))
        let index = makeIndex()
        do {
            _ = try await makePusher(index).push([record(1)], kinds: ["word"])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .http(status: 401, code: "boom"))
        }
        XCTAssertTrue(index.itemIDs(ofKind: "word").isEmpty)
    }

    func testContentHashIgnoresKeyOrderAndNoticesChanges() {
        let a = MirrorRecord(kind: "word", recordID: "1", payload: .object(["x": .number(1), "y": .string("z"), "list": .array([.string("a")])]))
        let b = MirrorRecord(kind: "word", recordID: "1", payload: .object(["list": .array([.string("a")]), "y": .string("z"), "x": .number(1)]))
        let c = MirrorRecord(kind: "word", recordID: "1", payload: .object(["x": .number(2), "y": .string("z"), "list": .array([.string("a")])]))
        XCTAssertEqual(a.contentHash, b.contentHash)
        XCTAssertNotEqual(a.contentHash, c.contentHash)
        XCTAssertEqual(a.contentHash.count, 64)
    }

    func testArabicAndMarkupSurviveTheRoundTripUnchanged() async throws {
        let (requests, _) = server()
        let arabic = "مرحبا بالعالم"
        let markup = "<img src=x onerror=alert(1)>"
        _ = try await makePusher(makeIndex()).push([record(1, text: arabic), record(2, text: markup)], kinds: ["word"])
        let sent = try items(try XCTUnwrap(requests.value.first))
        XCTAssertEqual((try open(sent[0])["d"] as? [String: Any])?["spanish"] as? String, arabic)
        XCTAssertEqual((try open(sent[1])["d"] as? [String: Any])?["spanish"] as? String, markup)
    }
}
