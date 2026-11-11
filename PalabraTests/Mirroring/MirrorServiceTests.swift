import XCTest
@testable import Palabra

@MainActor
final class MirrorServiceTests: XCTestCase {
    private var account = ""
    private var suite = ""
    private var directory: URL!
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        account = "mirror-service-test-\(UUID().uuidString)"
        suite = "mirror-service-test-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-service-\(UUID().uuidString)", isDirectory: true)
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        KeychainStore(account: account).delete()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: Fixtures

    private var indexFile: URL { directory.appendingPathComponent("index.json") }

    private func pairedSecrets() -> MirrorSecrets {
        MirrorSecrets(
            origin: "https://x.test", mirrorID: "MIR", ownerDeviceID: "own", ownerToken: "tok",
            dataKey: Base64URL.encode(Data(repeating: 9, count: 32)),
            computers: [MirrorComputer(id: "b1", name: "Computer 1", pairedAt: Date(timeIntervalSince1970: 0))]
        )
    }

    private func makeService(paired: Bool = true, enabled: Bool = true) -> MirrorService {
        let store = MirrorSecretsStore(keychain: KeychainStore(account: account))
        if paired { XCTAssertTrue(store.save(pairedSecrets())) }
        let settings = MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!)
        settings.value = MirrorSettings(enabled: enabled)
        return MirrorService(secrets: store, settings: settings, index: MirrorIndex(fileURL: indexFile), session: MockURLProtocol.session(), now: { self.clock })
    }

    private func record(_ n: Int) -> MirrorRecord {
        MirrorRecord(kind: "word", recordID: "r\(n)", payload: .object(["spanish": .string("palabra \(n)")]))
    }

    private func respond(status: Int = 200, json: String = #"{"seq":1}"#) -> Box<[URLRequest]> {
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            return (status, Data(json.utf8))
        }
        return seen
    }

    /// The words-only sync the older tests were written for.
    private func sync(_ service: MirrorService, _ records: [MirrorRecord], force: Bool = false) async {
        await service.sync(collections: [MirrorCollection(kind: "word", records: records)], force: force)
    }

    // MARK: Tests

    func testUnpairedSyncSendsNothing() async {
        let seen = respond()
        let service = makeService(paired: false)
        XCTAssertFalse(service.isPaired)
        await sync(service, [record(1)], force: true)
        XCTAssertTrue(seen.value.isEmpty)
        XCTAssertNil(service.lastSyncAt)
    }

    func testAMirrorThatIsOffNeverTouchesTheNetwork() async {
        let seen = respond()
        let service = makeService(enabled: false)
        await sync(service, [record(1)])
        XCTAssertTrue(seen.value.isEmpty)
    }

    func testPairedAndEnabledSyncPushesAndRemembersWhen() async {
        let seen = respond()
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertEqual(seen.value.count, 2, "the items, then the manifest")
        XCTAssertEqual(seen.value.map(\.httpMethod), ["PUT", "PUT"])
        XCTAssertEqual(service.lastSyncAt, clock)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!).value.lastSyncAt, clock, "the time is kept for the next launch")
    }

    func testASecondSyncWithinThirtySecondsIsSkippedUnlessForced() async {
        let seen = respond()
        let service = makeService()
        await sync(service, [record(1)])
        clock = clock.addingTimeInterval(10)
        await sync(service, [record(1), record(2)])
        XCTAssertEqual(seen.value.count, 2, "skipped: too soon")
        await sync(service, [record(1), record(2)], force: true)
        XCTAssertEqual(seen.value.count, 4, "forced: the new record goes out, then a new manifest")
        clock = clock.addingTimeInterval(5)
        let before = service.lastSyncAt
        await sync(service, [record(1), record(2)], force: true)
        XCTAssertEqual(seen.value.count, 4, "nothing changed, so no PUT")
        XCTAssertNotEqual(service.lastSyncAt, before, "but the sync time still moves")
        clock = clock.addingTimeInterval(31)
        await sync(service, [record(1), record(2), record(3)])
        XCTAssertEqual(seen.value.count, 6, "after 30 seconds it runs again")
    }

    func testRejectedKeepsTheLastSyncTimeAndReportsIt() async {
        _ = respond()
        let service = makeService()
        await sync(service, [record(1)])
        let good = service.lastSyncAt
        _ = respond(status: 401, json: #"{"error":"unauthorized"}"#)
        clock = clock.addingTimeInterval(60)
        await sync(service, [record(1), record(2)])
        XCTAssertEqual(service.lastError, .rejected)
        XCTAssertEqual(service.lastSyncAt, good)
    }

    func testOfflineAndRateLimitAreReported() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertEqual(service.lastError, .offline)
        _ = respond(status: 429, json: #"{"error":"rate_limited"}"#)
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(service.lastError, .rateLimited)
    }

    func testRemovingAComputerRevokesItFirst() async throws {
        let seen = respond()
        let service = makeService()
        await service.remove(computerID: "b1")
        let request = try XCTUnwrap(seen.value.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/m/MIR/devices/b1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer own.tok")
        XCTAssertTrue(service.computers.isEmpty)
    }

    func testAFailedRevokeKeepsTheComputerListed() async {
        _ = respond(status: 500, json: #"{"error":"internal"}"#)
        let service = makeService()
        await service.remove(computerID: "b1")
        XCTAssertEqual(service.computers.map(\.id), ["b1"])
        XCTAssertEqual(service.lastError, .other)
    }

    func testTurnOffAndForgetClearsEverythingOnThePhone() async throws {
        let seen = respond()
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.path))
        service.turnOffAndForget()
        XCTAssertFalse(service.isPaired)
        XCTAssertFalse(service.enabled)
        XCTAssertNil(service.lastSyncAt)
        XCTAssertNil(MirrorSecretsStore(keychain: KeychainStore(account: account)).load())
        XCTAssertTrue(MirrorIndex(fileURL: indexFile).itemIDs(ofKind: "word").isEmpty)
        let count = seen.value.count
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(seen.value.count, count, "nothing is sent once forgotten")
    }

    func testDidPairPicksUpTheSecretsAndTurnsMirroringOn() {
        let service = makeService(paired: false, enabled: false)
        XCTAssertFalse(service.isPaired)
        XCTAssertTrue(MirrorSecretsStore(keychain: KeychainStore(account: account)).save(pairedSecrets()))
        service.didPair()
        XCTAssertTrue(service.isPaired)
        XCTAssertTrue(service.enabled)
        XCTAssertEqual(service.computers.count, 1)
    }

    // MARK: Manifest

    private func sealedItems(_ request: URLRequest) throws -> [(id: String, sealed: Data)] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let list = try XCTUnwrap(body["items"] as? [[String: Any]])
        return try list.map { (id: try XCTUnwrap($0["id"] as? String), sealed: try XCTUnwrap(Base64URL.decode(try XCTUnwrap($0["sealed"] as? String)))) }
    }

    private func opened(_ request: URLRequest) throws -> [String: Any] {
        let keys = try XCTUnwrap(MirrorKeys(dataKey: Data(repeating: 9, count: 32)))
        let item = try XCTUnwrap(try sealedItems(request).first)
        let plain = try MirrorCrypto.openItem(keys: keys, itemID: item.id, sealed: item.sealed)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
    }

    func testTheManifestFollowsTheItemsAndDescribesThem() async throws {
        let seen = respond()
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertEqual(seen.value.count, 2)
        let manifest = try opened(seen.value[1])
        XCTAssertEqual(manifest["k"] as? String, "manifest")
        XCTAssertEqual(manifest["r"] as? String, "manifest")
        let payload = try XCTUnwrap(manifest["d"] as? [String: Any])
        XCTAssertEqual(payload["counts"] as? [String: Int], ["word": 1])
        let dataItem = try XCTUnwrap(try sealedItems(seen.value[0]).first)
        XCTAssertEqual(payload["idsHash"] as? String, MirrorManifest.idsHash([dataItem.id]))
        XCTAssertEqual(payload["pushedAt"] as? String, "2023-11-14T22:13:20Z", "the clock, as ISO-8601 UTC")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(manifest["g"] as? Int), try XCTUnwrap(opened(seen.value[0])["g"] as? Int), "the manifest is never older than the items")
    }

    func testTheManifestIsSkippedWhenNothingChangedUntilTheHeartbeat() async throws {
        let seen = respond()
        let service = makeService()
        await sync(service, [record(1)])
        clock = clock.addingTimeInterval(5)
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(seen.value.count, 2, "nothing changed and the manifest is fresh")
        clock = clock.addingTimeInterval(601)
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(seen.value.count, 3, "exactly one more PUT")
        XCTAssertEqual(try opened(seen.value[2])["k"] as? String, "manifest")
    }

    func testAFailedManifestIsRetriedOnTheNextSync() async throws {
        let puts = Box<Int>(0)
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            puts.value += 1
            return puts.value == 2 ? (500, Data(#"{"error":"internal"}"#.utf8)) : (200, Data(#"{"seq":1}"#.utf8))
        }
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertEqual(service.lastError, .other)
        XCTAssertNil(MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!).value.lastManifestIDsHash)
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(seen.value.count, 3, "the items were already accepted: only a manifest goes out")
        XCTAssertEqual(try opened(seen.value[2])["k"] as? String, "manifest")
        XCTAssertNil(service.lastError)
        XCTAssertNotNil(MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!).value.lastManifestIDsHash)
    }

    func testNoRecordsStillGetsAnEmptyManifestOnce() async throws {
        let seen = respond()
        let service = makeService()
        await sync(service, [])
        XCTAssertEqual(seen.value.count, 1)
        let manifest = try opened(seen.value[0])
        let payload = try XCTUnwrap(manifest["d"] as? [String: Any])
        XCTAssertEqual((payload["counts"] as? [String: Int])?.isEmpty, true)
        XCTAssertEqual(payload["idsHash"] as? String, MirrorManifest.idsHash([]))
        await sync(service, [], force: true)
        XCTAssertEqual(seen.value.count, 1, "unchanged and fresh: no second manifest")
    }

    // MARK: Collections

    private func deck(_ n: Int) -> MirrorRecord {
        MirrorRecord(kind: "deck", recordID: "d\(n)", payload: .object(["name": .string("deck \(n)")]))
    }

    func testAKindMissingFromTheCollectionsIsNeverTombstoned() async throws {
        let seen = respond()
        let service = makeService()
        await service.sync(collections: [MirrorCollection(kind: "word", records: [record(1)]), MirrorCollection(kind: "deck", records: [deck(1)])], force: true)
        let before = seen.value.count

        await service.sync(collections: [MirrorCollection(kind: "word", records: [record(1)])], force: true)
        XCTAssertEqual(seen.value.count, before, "the deck kind was not built this time, so its item stays on the Worker")

        await service.sync(collections: [MirrorCollection(kind: "word", records: [record(1)]), MirrorCollection(kind: "deck", records: [])], force: true)
        let bodies = try seen.value.dropFirst(before).map { try XCTUnwrap(String(data: try XCTUnwrap($0.httpBody), encoding: .utf8)) }
        XCTAssertTrue(bodies.contains { $0.contains(#""deleted":true"#) }, "a built but empty kind tombstones what was pushed before")
    }

    func testMirrorFullIsReported() async {
        _ = respond(status: 409, json: #"{"error":"mirror_full"}"#)
        let service = makeService()
        await sync(service, [record(1)])
        XCTAssertEqual(service.lastError, .full)
    }

    // MARK: Every collection

    private func allCollections(words: Int, deckName: String = "deck") -> [MirrorCollection] {
        func make(_ kind: String, _ n: Int) -> [MirrorRecord] {
            (0..<n).map { MirrorRecord(kind: kind, recordID: "\(kind)\($0)", payload: .object(["name": .string(kind == "deck" ? deckName : "x\($0)")])) }
        }
        return [
            MirrorCollection(kind: "word", records: make("word", words)),
            MirrorCollection(kind: "deck", records: make("deck", 1)),
            MirrorCollection(kind: "card", records: make("card", 3)),
            MirrorCollection(kind: "stats", records: make("stats", 1)),
            MirrorCollection(kind: "review", records: make("review", 2)),
            MirrorCollection(kind: "artifact", records: make("artifact", 2)),
            MirrorCollection(kind: "chat", records: make("chat", 1)),
            MirrorCollection(kind: "lesson", records: make("lesson", 2)),
            MirrorCollection(kind: "lessonPage", records: make("lessonPage", 3)),
        ]
    }

    func testAllCollectionsGoOutInBatchesOfAtMost200ItemsAndTheManifestCountsEachKind() async throws {
        let seen = respond()
        let service = makeService()
        await service.sync(collections: allCollections(words: 450), force: true)
        // 450 words + 15 others = 465 items: 200 + 200 + 65, then the manifest alone
        let sizes = try seen.value.map { try sealedItems($0).count }
        XCTAssertEqual(sizes, [200, 200, 65, 1])
        for request in seen.value {
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertLessThan(body.count, 1_000_000)
        }
        let counts = try XCTUnwrap(opened(try XCTUnwrap(seen.value.last))["d"] as? [String: Any])["counts"] as? [String: Int]
        XCTAssertEqual(counts, ["word": 450, "deck": 1, "card": 3, "stats": 1, "review": 2, "artifact": 2, "chat": 1, "lesson": 2, "lessonPage": 3])
    }

    func testAnIdenticalSecondSyncSendsNothingUntilTheHeartbeatThenOnlyTheManifest() async throws {
        let seen = respond()
        let service = makeService()
        await service.sync(collections: allCollections(words: 5), force: true)
        let first = seen.value.count
        clock = clock.addingTimeInterval(40)
        await service.sync(collections: allCollections(words: 5))
        XCTAssertEqual(seen.value.count, first, "nothing changed and the manifest is fresh")
        clock = clock.addingTimeInterval(MirrorManifest.heartbeat)
        await service.sync(collections: allCollections(words: 5))
        XCTAssertEqual(seen.value.count, first + 1, "after the heartbeat: one request")
        XCTAssertEqual(try opened(try XCTUnwrap(seen.value.last))["k"] as? String, "manifest")
    }

    func testChangingOneDeckSendsExactlyThatItemAndAManifest() async throws {
        let seen = respond()
        let service = makeService()
        await service.sync(collections: allCollections(words: 5), force: true)
        let first = seen.value.count
        clock = clock.addingTimeInterval(40)
        await service.sync(collections: allCollections(words: 5, deckName: "renamed"))
        XCTAssertEqual(seen.value.count, first + 2)
        XCTAssertEqual(try sealedItems(seen.value[first]).count, 1)
        XCTAssertEqual(try opened(seen.value[first])["k"] as? String, "deck")
        XCTAssertEqual(try opened(seen.value[first + 1])["k"] as? String, "manifest")
    }
}
