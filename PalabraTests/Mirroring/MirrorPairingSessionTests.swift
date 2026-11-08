import CryptoKit
import XCTest
@testable import Palabra

@MainActor
final class MirrorPairingSessionTests: XCTestCase {
    private var vectors: MirrorVectors!
    private var account = ""
    private let origin = URL(string: "https://x.test")!

    override func setUpWithError() throws {
        vectors = try MirrorVectors.load()
        account = "mirror-secrets-test-\(UUID().uuidString)"
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        KeychainStore(account: account).delete()
        super.tearDown()
    }

    // MARK: Fixtures

    /// A fake Worker: answers each route, records every request, and fails the routes named in `failing`.
    private final class Server: @unchecked Sendable {
        let requests = Box<[URLRequest]>([])
        let failing = Box<[String: (Int, String)]>([:])
        func install() {
            let requests = requests, failing = failing
            MockURLProtocol.handler = { request in
                requests.value.append(request)
                let path = request.url?.path ?? ""
                let route = "\(request.httpMethod ?? "") \(path)"
                if let (status, code) = failing.value.first(where: { route.hasSuffix($0.key) })?.value {
                    return (status, Data(#"{"error":"\#(code)"}"#.utf8))
                }
                if path == "/api/mirrors" { return (201, Data(#"{"mirrorId":"MIR1","deviceId":"x"}"#.utf8)) }
                return (200, Data("{}".utf8))
            }
        }
        /// Requests whose "METHOD /path" ends or starts with `pattern`.
        func sent(_ pattern: String) -> [URLRequest] {
            requests.value.filter {
                let route = "\($0.httpMethod ?? "") \($0.url?.path ?? "")"
                return route.hasSuffix(pattern) || route.hasPrefix(pattern)
            }
        }
    }

    private func makeLink(origin: String = "https://x.test") throws -> PairingLink {
        PairingLink(
            origin: URL(string: origin)!, pairID: vectors.pair.pairId,
            browserPublic: Data(hex: vectors.pair.browserPubHex), nonce: Data(hex: vectors.pair.nonceHex)
        )
    }

    private func makeSession(_ server: Server, store: MirrorSecretsStore? = nil) throws -> (MirrorPairingSession, MirrorSecretsStore) {
        server.install()
        let secrets = store ?? MirrorSecretsStore(keychain: KeychainStore(account: account))
        let counter = Box<UInt8>(0)
        let session = MirrorPairingSession(
            link: try makeLink(),
            client: MirrorClient(origin: origin, session: MockURLProtocol.session()),
            secrets: secrets,
            makeKey: { (try? P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: self.vectors.pair.phonePrivHex))) ?? P256.KeyAgreement.PrivateKey() },
            randomBytes: { count in counter.value &+= 1; return Data(repeating: counter.value, count: count) },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return (session, secrets)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    // MARK: Tests

    func testJoinShowsTheVectorCodeAndSendsNothingElseYet() async throws {
        let server = Server()
        let (session, _) = try makeSession(server)
        await session.start()
        XCTAssertEqual(session.phase, .awaitingConfirmation(code: vectors.pair.matchCode))
        let join = try XCTUnwrap(server.sent("/join").first)
        let phonePub = try XCTUnwrap(json(join)["phonePub"] as? String)
        XCTAssertEqual(phonePub.count, 87)
        XCTAssertEqual(phonePub, Base64URL.encode(Data(hex: vectors.pair.phonePubHex)))
        XCTAssertEqual(server.requests.value.count, 1, "only the join so far")
        XCTAssertTrue(server.sent("/api/mirrors").isEmpty)
        XCTAssertTrue(server.sent("/devices").isEmpty)
        XCTAssertTrue(server.sent("/reply").isEmpty)
    }

    func testConfirmCreatesTheMirrorAddsTheComputerAndRepliesSealed() async throws {
        let server = Server()
        let (session, store) = try makeSession(server)
        await session.start()
        await session.confirm()
        XCTAssertEqual(session.phase, .done)

        let saved = try XCTUnwrap(store.load())
        let create = try XCTUnwrap(server.sent("POST /api/mirrors").first)
        XCTAssertEqual(try json(create)["ownerTokenHash"] as? String, MirrorCrypto.sha256Hex(saved.ownerToken))
        XCTAssertEqual(saved.mirrorID, "MIR1")
        XCTAssertEqual(saved.origin, "https://x.test")
        XCTAssertEqual(saved.computers.count, 1)
        XCTAssertEqual(saved.computers.first?.name, "Computer 1")

        let add = try XCTUnwrap(server.sent("/api/m/MIR1/devices").first)
        XCTAssertEqual(add.value(forHTTPHeaderField: "Authorization"), "Bearer \(saved.bearer)")
        let tokenHash = try XCTUnwrap(json(add)["tokenHash"] as? String)

        // Open the reply the way the browser does.
        let reply = try XCTUnwrap(server.sent("/reply").first)
        let sealed = try XCTUnwrap(Base64URL.decode(try XCTUnwrap(json(reply)["sealed"] as? String)))
        let browser = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: vectors.pair.browserPrivHex))
        let kPair = try MirrorCrypto.agree(privateKey: browser, otherPublic: Data(hex: vectors.pair.phonePubHex), nonce: Data(hex: vectors.pair.nonceHex))
        let wrap = try XCTUnwrap(JSONSerialization.jsonObject(with: try MirrorCrypto.openWrap(key: kPair, pairID: vectors.pair.pairId, sealed: sealed)) as? [String: Any])
        XCTAssertEqual(wrap["v"] as? Int, 1)
        XCTAssertEqual(wrap["mirrorId"] as? String, "MIR1")
        XCTAssertEqual(wrap["dataKey"] as? String, saved.dataKey)
        XCTAssertEqual(MirrorCrypto.sha256Hex(try XCTUnwrap(wrap["deviceToken"] as? String)), tokenHash)
        XCTAssertEqual(wrap["deviceId"] as? String, saved.computers.first?.id)
    }

    func testNoSecretAppearsInAnyURLOrBodyInTheClear() async throws {
        let server = Server()
        let (session, store) = try makeSession(server)
        await session.start()
        await session.confirm()
        let saved = try XCTUnwrap(store.load())
        let reply = try XCTUnwrap(server.sent("/reply").first)
        let browser = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: vectors.pair.browserPrivHex))
        let kPair = try MirrorCrypto.agree(privateKey: browser, otherPublic: Data(hex: vectors.pair.phonePubHex), nonce: Data(hex: vectors.pair.nonceHex))
        let wrap = try XCTUnwrap(JSONSerialization.jsonObject(with: try MirrorCrypto.openWrap(key: kPair, pairID: vectors.pair.pairId, sealed: try XCTUnwrap(Base64URL.decode(try XCTUnwrap(json(reply)["sealed"] as? String))))) as? [String: Any])
        let secrets = [saved.ownerToken, saved.dataKey, try XCTUnwrap(wrap["deviceToken"] as? String)]
        for request in server.requests.value {
            let url = request.url?.absoluteString ?? ""
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            for secret in secrets {
                XCTAssertFalse(url.contains(secret), "\(url) leaks a secret")
                XCTAssertFalse(body.contains(secret), "\(url) body leaks a secret")
            }
        }
    }

    func testADoubleConfirmPairsOnce() async throws {
        let server = Server()
        let (session, _) = try makeSession(server)
        await session.start()
        async let first: Void = session.confirm()
        async let second: Void = session.confirm()
        _ = await (first, second)
        await session.confirm()
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(server.sent("POST /api/mirrors").count, 1)
        XCTAssertEqual(server.sent("/devices").count, 1)
        XCTAssertEqual(server.sent("/reply").count, 1)
    }

    func testExistingSecretsForTheSameOriginAddAnotherComputerWithoutANewMirror() async throws {
        let server = Server()
        let store = MirrorSecretsStore(keychain: KeychainStore(account: account))
        let existing = MirrorSecrets(
            origin: "https://x.test", mirrorID: "OLD", ownerDeviceID: "own", ownerToken: "tok", dataKey: Base64URL.encode(Data(count: 32)),
            computers: [MirrorComputer(id: "b0", name: "Computer 1", pairedAt: Date(timeIntervalSince1970: 0))]
        )
        XCTAssertTrue(store.save(existing))
        let (session, _) = try makeSession(server, store: store)
        await session.start()
        await session.confirm()
        XCTAssertEqual(session.phase, .done)
        XCTAssertTrue(server.sent("POST /api/mirrors").isEmpty)
        XCTAssertEqual(server.sent("/api/m/OLD/devices").count, 1)
        XCTAssertEqual(store.load()?.computers.map(\.name), ["Computer 1", "Computer 2"])
    }

    func testSecretsForAnotherOriginFailWithoutAnyRequest() async throws {
        let server = Server()
        let store = MirrorSecretsStore(keychain: KeychainStore(account: account))
        XCTAssertTrue(store.save(MirrorSecrets(origin: "https://other.test", mirrorID: "M", ownerDeviceID: "o", ownerToken: "t", dataKey: "k", computers: [])))
        let (session, _) = try makeSession(server, store: store)
        await session.start()
        XCTAssertEqual(session.phase, .failed(.alreadyPairedElsewhere))
        XCTAssertTrue(server.requests.value.isEmpty)
    }

    func testJoinFailuresMapToClearReasons() async throws {
        for (status, code, expected) in [(409, "slot_taken", MirrorPairingSession.Failure.slotTaken), (410, "gone", .expired), (404, "not_found", .expired), (429, "rate_limited", .rateLimited)] {
            let server = Server()
            server.failing.value = ["/join": (status, code)]
            let (session, _) = try makeSession(server)
            await session.start()
            XCTAssertEqual(session.phase, .failed(expected), code)
        }
    }

    func testDeviceFailureAfterCreateKeepsSecretsAndSendsNoReply() async throws {
        let server = Server()
        server.failing.value = ["POST /api/m/MIR1/devices": (409, "too_many_devices")]
        let (session, store) = try makeSession(server)
        await session.start()
        await session.confirm()
        XCTAssertEqual(session.phase, .failed(.tooManyComputers))
        XCTAssertNotNil(store.load(), "the mirror exists on the Worker, so its secrets are kept")
        XCTAssertTrue(server.sent("/reply").isEmpty)
        XCTAssertTrue(server.sent("DELETE").isEmpty, "nothing was added, so nothing to remove")
    }

    func testReplyFailureRemovesTheComputerAgain() async throws {
        let server = Server()
        server.failing.value = ["/reply": (500, "internal")]
        let (session, store) = try makeSession(server)
        await session.start()
        await session.confirm()
        XCTAssertEqual(session.phase, .failed(.other))
        XCTAssertEqual(server.sent("DELETE").count, 1)
        XCTAssertEqual(store.load()?.computers.count, 0, "a computer that never got its keys is not listed")
    }

    func testCancelTellsTheWorkerAndStops() async throws {
        let server = Server()
        let (session, _) = try makeSession(server)
        await session.start()
        await session.cancel()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertEqual(server.sent("/cancel").count, 1)
        await session.confirm()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertTrue(server.sent("/devices").isEmpty)
    }

    func testABadKeyInTheLinkSendsNothing() async throws {
        let server = Server()
        server.install()
        var offCurve = Data(hex: vectors.pair.browserPubHex)
        offCurve[64] ^= 1
        let link = PairingLink(origin: origin, pairID: vectors.pair.pairId, browserPublic: offCurve, nonce: Data(hex: vectors.pair.nonceHex))
        let session = MirrorPairingSession(link: link, client: MirrorClient(origin: origin, session: MockURLProtocol.session()), secrets: MirrorSecretsStore(keychain: KeychainStore(account: account)))
        await session.start()
        XCTAssertEqual(session.phase, .failed(.other))
        XCTAssertTrue(server.requests.value.isEmpty)
    }
}
