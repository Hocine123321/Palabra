import XCTest
@testable import Palabra

final class MirrorClientTests: XCTestCase {
    private let origin = URL(string: "https://x.test")!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    /// Answers every request with `status` and `json`, and keeps what was sent.
    private func capture(status: Int = 200, json: String = "{}") -> Box<[URLRequest]> {
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            return (status, Data(json.utf8))
        }
        return seen
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func client(_ url: URL? = nil) -> MirrorClient { MirrorClient(origin: url ?? origin, session: MockURLProtocol.session()) }

    func testCreateMirrorSendsOnlyTheHashAndReturnsTheID() async throws {
        let seen = capture(status: 201, json: #"{"mirrorId":"MIR123","deviceId":"dev"}"#)
        let id = try await client().createMirror(deviceID: "dev", ownerTokenHash: String(repeating: "a", count: 64))
        XCTAssertEqual(id, "MIR123")
        let request = try XCTUnwrap(seen.value.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://x.test/api/mirrors")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let sent = try body(request)
        XCTAssertEqual(Set(sent.keys), ["deviceId", "ownerTokenHash"])
        XCTAssertEqual(sent["ownerTokenHash"] as? String, String(repeating: "a", count: 64))
    }

    func testPairJoinAndReplyBodies() async throws {
        let seen = capture()
        let publicKey = Data(repeating: 4, count: 65)
        try await client().pairJoin(pairID: "PAIR", phonePublic: publicKey)
        try await client().pairReply(pairID: "PAIR", sealed: Data([1, 2, 3]))
        try await client().pairCancel(pairID: "PAIR")
        XCTAssertEqual(seen.value.map { $0.url?.path }, ["/api/pair/PAIR/join", "/api/pair/PAIR/reply", "/api/pair/PAIR/cancel"])
        let join = try body(seen.value[0])
        XCTAssertEqual(Set(join.keys), ["phonePub"])
        XCTAssertEqual((join["phonePub"] as? String)?.count, 87)
        XCTAssertEqual(Base64URL.decode(join["phonePub"] as? String ?? ""), publicKey)
        let reply = try body(seen.value[1])
        XCTAssertEqual(Set(reply.keys), ["sealed"])
        XCTAssertEqual(reply["sealed"] as? String, Base64URL.encode(Data([1, 2, 3])))
        XCTAssertNil(seen.value[2].httpBody)
    }

    func testDeviceCallsCarryTheBearer() async throws {
        let seen = capture()
        try await client().addDevice(mirrorID: "MIR", bearer: "own.tok", deviceID: "b1", tokenHash: "h")
        try await client().removeDevice(mirrorID: "MIR", bearer: "own.tok", deviceID: "b1")
        XCTAssertEqual(seen.value.map { $0.httpMethod }, ["POST", "DELETE"])
        XCTAssertEqual(seen.value.map { $0.url?.path }, ["/api/m/MIR/devices", "/api/m/MIR/devices/b1"])
        XCTAssertEqual(seen.value.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer own.tok", "Bearer own.tok"])
        XCTAssertEqual(Set(try body(seen.value[0]).keys), ["deviceId", "tokenHash"])
    }

    func testPutItemsBodyAndSeq() async throws {
        let seen = capture(json: #"{"seq":42}"#)
        let seq = try await client().putItems(mirrorID: "MIR", bearer: "own.tok", items: [
            PutItem(id: "id1", sealed: "AAAA", deleted: false),
            PutItem(id: "id2", sealed: "ignored", deleted: true),
        ])
        XCTAssertEqual(seq, 42)
        let request = try XCTUnwrap(seen.value.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/m/MIR/items")
        let items = try XCTUnwrap(try body(request)["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["id"] as? String, "id1")
        XCTAssertEqual(items[0]["sealed"] as? String, "AAAA")
        XCTAssertNil(items[0]["deleted"])
        XCTAssertEqual(items[1]["deleted"] as? Bool, true)
        XCTAssertEqual(items[1]["sealed"] as? String, "", "a tombstone sends no ciphertext")
    }

    func testStateReturnsSeqAndEpoch() async throws {
        let seen = capture(json: #"{"seq":7,"epoch":2}"#)
        let state = try await client().state(mirrorID: "MIR", bearer: "a.b")
        XCTAssertEqual(state, MirrorState(seq: 7, epoch: 2))
        XCTAssertEqual(seen.value.first?.httpMethod, "GET")
    }

    func testStateWithoutEpochIsEpochZero() async throws {
        _ = capture(json: #"{"seq":7}"#)
        let state = try await client().state(mirrorID: "MIR", bearer: "a.b")
        XCTAssertEqual(state, MirrorState(seq: 7, epoch: 0))
    }

    func testRotateSendsTheEpochTheRemovedDeviceAndTheBlobs() async throws {
        let seen = capture(json: #"{"ok":true,"epoch":3}"#)
        let confirmed = try await client().rotate(mirrorID: "MIR", bearer: "a.b", epoch: 3, remove: "DEV1", blobs: ["DEV2": "blob2"])
        XCTAssertEqual(confirmed, 3)
        let request = try XCTUnwrap(seen.value.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/m/MIR/rotate")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer a.b")
        let sent = try body(request)
        XCTAssertEqual(Set(sent.keys), ["epoch", "remove", "blobs"])
        XCTAssertEqual(sent["epoch"] as? Int, 3)
        XCTAssertEqual(sent["remove"] as? String, "DEV1")
        XCTAssertEqual(sent["blobs"] as? [String: String], ["DEV2": "blob2"])
    }

    func testRotateFailureKeepsStatusAndCode() async {
        _ = capture(status: 409, json: #"{"error":"stale_epoch"}"#)
        do {
            _ = try await client().rotate(mirrorID: "MIR", bearer: "a.b", epoch: 1, remove: nil, blobs: [:])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .http(status: 409, code: "stale_epoch"))
        }
    }

    func testHTTPErrorsKeepStatusAndCode() async {
        for (status, code) in [(409, "slot_taken"), (429, "rate_limited"), (401, "unauthorized")] {
            _ = capture(status: status, json: #"{"error":"\#(code)"}"#)
            do {
                try await client().pairJoin(pairID: "P", phonePublic: Data(count: 65))
                XCTFail("should throw")
            } catch {
                XCTAssertEqual(error as? MirrorClientError, .http(status: status, code: code))
            }
        }
        _ = capture(status: 502, json: "<html>")
        do {
            try await client().pairCancel(pairID: "P")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .http(status: 502, code: "unknown"))
        }
    }

    func testTransportFailureIsOffline() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client().state(mirrorID: "M", bearer: "a.b")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .offline)
        }
    }

    func testNonJSONSuccessIsABadResponse() async {
        _ = capture(status: 200, json: "not json")
        do {
            _ = try await client().createMirror(deviceID: "d", ownerTokenHash: "h")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MirrorClientError, .badResponse)
        }
    }

    func testPortAndPathPrefixAreRespected() async throws {
        let seen = capture(json: #"{"seq":1}"#)
        _ = try await client(URL(string: "https://x.test:8443/mirror/")!).state(mirrorID: "M", bearer: "a.b")
        XCTAssertEqual(seen.value.first?.url?.absoluteString, "https://x.test:8443/mirror/api/m/M/state")
    }
}
