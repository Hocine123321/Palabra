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

    private func makeService(paired: Bool = true, enabled: Bool = true, secrets: MirrorSecrets? = nil) -> MirrorService {
        let store = MirrorSecretsStore(keychain: KeychainStore(account: account))
        if paired { XCTAssertTrue(store.save(secrets ?? pairedSecrets())) }
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

    // MARK: Removing a computer rotates the key

    private let oldKey = Base64URL.encode(Data(repeating: 9, count: 32))

    private func deviceKey(_ n: UInt8) -> String { Base64URL.encode(Data(repeating: n, count: 32)) }

    private func computer(_ id: String, key: UInt8?) -> MirrorComputer {
        MirrorComputer(id: id, name: "Computer \(id)", pairedAt: Date(timeIntervalSince1970: 0), deviceKey: key.map(deviceKey))
    }

    private func secrets(computers: [MirrorComputer]) -> MirrorSecrets {
        MirrorSecrets(origin: "https://x.test", mirrorID: "MIR", ownerDeviceID: "own", ownerToken: "tok", dataKey: oldKey, computers: computers)
    }

    private func savedSecrets() -> MirrorSecrets? {
        MirrorSecretsStore(keychain: KeychainStore(account: account)).load()
    }

    /// The rotate request's JSON body.
    private func rotateBody(_ seen: Box<[URLRequest]>) throws -> [String: Any] {
        let request = try XCTUnwrap(seen.value.first { $0.url?.path == "/api/m/MIR/rotate" })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer own.tok")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testRemovingAComputerSealsTheNewKeyToEachRemainingComputerAndSendsEverythingAgain() async throws {
        let seen = Box<[URLRequest]>([])
        let pendingDuringRequest = Box<MirrorSecrets.Pending?>(nil)
        let account = account
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            if request.url?.path.hasSuffix("/rotate") == true {
                // The new key must already be in the Keychain when the Worker is asked to switch.
                pendingDuringRequest.value = MirrorSecretsStore(keychain: KeychainStore(account: account)).load()?.pending
            }
            return (200, Data(#"{"ok":true,"epoch":1,"seq":1}"#.utf8))
        }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]))
        await sync(service, [record(1)])
        XCTAssertFalse(MirrorIndex(fileURL: indexFile).itemIDs(ofKind: "word").isEmpty)

        await service.remove(computerID: "b1")

        let sent = try rotateBody(seen)
        XCTAssertEqual(sent["epoch"] as? Int, 1)
        XCTAssertEqual(sent["remove"] as? String, "b1")
        let blobs = try XCTUnwrap(sent["blobs"] as? [String: String])
        XCTAssertEqual(Set(blobs.keys), ["b2"])

        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved.epoch, 1)
        XCTAssertNil(saved.pending)
        XCTAssertNotEqual(saved.dataKey, oldKey)
        XCTAssertEqual(saved.computers.map(\.id), ["b2"])
        XCTAssertEqual(service.computers.map(\.id), ["b2"])
        XCTAssertEqual(pendingDuringRequest.value, MirrorSecrets.Pending(dataKey: saved.dataKey, epoch: 1, removedIDs: ["b1"]))

        // What the remaining computer receives opens to exactly the key the phone now uses.
        let sealed = try XCTUnwrap(Base64URL.decode(try XCTUnwrap(blobs["b2"])))
        let opened = try MirrorCrypto.openRotation(deviceKey: Data(repeating: 2, count: 32), mirrorID: "MIR", deviceID: "b2", epoch: 1, sealed: sealed)
        XCTAssertEqual(Base64URL.encode(opened), saved.dataKey)
        XCTAssertThrowsError(try MirrorCrypto.openRotation(deviceKey: Data(repeating: 1, count: 32), mirrorID: "MIR", deviceID: "b2", epoch: 1, sealed: sealed), "the removed computer's key opens nothing")

        // The Worker's copy was deleted, so the phone forgets what it pushed and sends it all again.
        XCTAssertTrue(MirrorIndex(fileURL: indexFile).itemIDs(ofKind: "word").isEmpty)
        let before = seen.value.count
        await sync(service, [record(1)], force: true)
        let puts = seen.value.dropFirst(before).filter { $0.httpMethod == "PUT" }
        XCTAssertFalse(puts.isEmpty)
    }

    func testRemovingTheLastComputerStillReplacesTheKeyWithNoBlobs() async throws {
        let seen = respond(json: #"{"ok":true,"epoch":1}"#)
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1)]))
        await service.remove(computerID: "b1")
        XCTAssertEqual(try XCTUnwrap(rotateBody(seen)["blobs"] as? [String: String]), [:])
        XCTAssertEqual(seen.value.count, 1, "one call revokes the token and replaces the key")
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved.epoch, 1)
        XCTAssertNotEqual(saved.dataKey, oldKey)
        XCTAssertTrue(saved.computers.isEmpty)
    }

    func testAComputerPairedBeforeRotationIsDroppedWithTheRemovedOne() async throws {
        let seen = respond(json: #"{"ok":true,"epoch":1}"#)
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b3", key: nil), computer("b2", key: 2)]))
        XCTAssertEqual(service.computersNeedingRepair.map(\.id), ["b3"])
        await service.remove(computerID: "b1")
        XCTAssertEqual(Set(try XCTUnwrap(rotateBody(seen)["blobs"] as? [String: String]).keys), ["b2"])
        XCTAssertEqual(service.computers.map(\.id), ["b2"])
        XCTAssertEqual(service.lastDroppedNames, ["Computer b3"])
        XCTAssertTrue(service.computersNeedingRepair.isEmpty)
    }

    func testAnOfflineRemovalKeepsTheOldKeyAndTheComputerAndIsSettledOnTheNextSync() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]))
        await service.remove(computerID: "b1")
        XCTAssertEqual(service.lastError, .offline)
        XCTAssertEqual(service.computers.map(\.id), ["b1", "b2"])
        let waiting = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(waiting.dataKey, oldKey, "the old key is still the live one")
        let pending = try XCTUnwrap(waiting.pending, "the new key is kept in case the Worker did take it")

        // The Worker did take the rotation (the reply was lost): the pending key becomes the key.
        let later = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            later.value.append(request)
            return (200, Data(#"{"seq":0,"epoch":1}"#.utf8))
        }
        let service2 = MirrorService(
            secrets: MirrorSecretsStore(keychain: KeychainStore(account: account)),
            settings: MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!),
            index: MirrorIndex(fileURL: indexFile), session: MockURLProtocol.session(), now: { self.clock }
        )
        service2.enabled = true
        await sync(service2, [record(1)], force: true)
        XCTAssertEqual(later.value.first?.httpMethod, "GET")
        XCTAssertEqual(later.value.first?.url?.path, "/api/m/MIR/state")
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved.dataKey, pending.dataKey)
        XCTAssertEqual(saved.epoch, 1)
        XCTAssertNil(saved.pending)
        XCTAssertEqual(saved.computers.map(\.id), ["b2"])
        XCTAssertTrue(later.value.contains { $0.httpMethod == "PUT" }, "the library goes out under the new key")
    }

    func testAPendingKeyTheWorkerNeverTookIsDropped() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1)]))
        await service.remove(computerID: "b1")
        XCTAssertNotNil(savedSecrets()?.pending)

        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            return (200, Data(#"{"seq":0,"epoch":0}"#.utf8))
        }
        await sync(service, [record(1)], force: true)
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertNil(saved.pending)
        XCTAssertEqual(saved.dataKey, oldKey)
        XCTAssertEqual(saved.epoch, 0)
        XCTAssertEqual(saved.computers.map(\.id), ["b1"])
        XCTAssertEqual(seen.value.first?.url?.path, "/api/m/MIR/state")
    }

    func testAnUnsettledRotationBlocksPushingUntilTheWorkerCanBeAsked() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1)]))
        await service.remove(computerID: "b1")
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in seen.value.append(request); throw URLError(.notConnectedToInternet) }
        await sync(service, [record(1)], force: true)
        XCTAssertEqual(service.lastError, .offline)
        XCTAssertTrue(seen.value.allSatisfy { $0.httpMethod == "GET" }, "only the state was asked; no item was sent under a key of unknown status")
        XCTAssertNotNil(savedSecrets()?.pending)
    }

    func testAStaleEpochChangesNothingAndLooksOnlyOnce() async throws {
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            if request.url?.path.hasSuffix("/rotate") == true { return (409, Data(#"{"error":"stale_epoch"}"#.utf8)) }
            return (200, Data(#"{"seq":1,"epoch":5}"#.utf8))
        }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]))
        await service.remove(computerID: "b1")
        XCTAssertEqual(seen.value.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }, ["POST /api/m/MIR/rotate", "GET /api/m/MIR/state"])
        XCTAssertEqual(service.lastError, .other)
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved, secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]), "nothing changed, not even a leftover pending key")
    }

    func testAStaleEpochThatTurnsOutToBeOurOwnRotationIsAdopted() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/rotate") == true { return (409, Data(#"{"error":"stale_epoch"}"#.utf8)) }
            return (200, Data(#"{"seq":1,"epoch":1}"#.utf8))
        }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]))
        await service.remove(computerID: "b1")
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved.epoch, 1)
        XCTAssertNil(saved.pending)
        XCTAssertEqual(saved.computers.map(\.id), ["b2"])
    }

    func testRemovingAComputerThatIsAlreadyGoneDoesNotRotate() async throws {
        let seen = Box<[URLRequest]>([])
        MockURLProtocol.handler = { request in
            seen.value.append(request)
            return (404, Data(#"{"error":"not_found"}"#.utf8))
        }
        let service = makeService(secrets: secrets(computers: [computer("b1", key: 1), computer("b2", key: 2)]))
        await service.remove(computerID: "b1")
        XCTAssertEqual(seen.value.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }, ["POST /api/m/MIR/rotate", "DELETE /api/m/MIR/devices/b1"])
        let saved = try XCTUnwrap(savedSecrets())
        XCTAssertEqual(saved.dataKey, oldKey)
        XCTAssertEqual(saved.epoch, 0)
        XCTAssertNil(saved.pending)
        XCTAssertEqual(saved.computers.map(\.id), ["b2"])
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
