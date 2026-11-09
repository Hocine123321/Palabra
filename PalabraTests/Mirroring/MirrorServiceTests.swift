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

    // MARK: Tests

    func testUnpairedSyncSendsNothing() async {
        let seen = respond()
        let service = makeService(paired: false)
        XCTAssertFalse(service.isPaired)
        await service.sync(records: [record(1)], force: true)
        XCTAssertTrue(seen.value.isEmpty)
        XCTAssertNil(service.lastSyncAt)
    }

    func testAMirrorThatIsOffNeverTouchesTheNetwork() async {
        let seen = respond()
        let service = makeService(enabled: false)
        await service.sync(records: [record(1)])
        XCTAssertTrue(seen.value.isEmpty)
    }

    func testPairedAndEnabledSyncPushesAndRemembersWhen() async {
        let seen = respond()
        let service = makeService()
        await service.sync(records: [record(1)])
        XCTAssertEqual(seen.value.count, 1)
        XCTAssertEqual(seen.value.first?.httpMethod, "PUT")
        XCTAssertEqual(service.lastSyncAt, clock)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(MirrorSettingsStore(defaults: UserDefaults(suiteName: suite)!).value.lastSyncAt, clock, "the time is kept for the next launch")
    }

    func testASecondSyncWithinThirtySecondsIsSkippedUnlessForced() async {
        let seen = respond()
        let service = makeService()
        await service.sync(records: [record(1)])
        clock = clock.addingTimeInterval(10)
        await service.sync(records: [record(1), record(2)])
        XCTAssertEqual(seen.value.count, 1, "skipped: too soon")
        await service.sync(records: [record(1), record(2)], force: true)
        XCTAssertEqual(seen.value.count, 2, "forced: the new record goes out")
        clock = clock.addingTimeInterval(5)
        let before = service.lastSyncAt
        await service.sync(records: [record(1), record(2)], force: true)
        XCTAssertEqual(seen.value.count, 2, "nothing changed, so no PUT")
        XCTAssertNotEqual(service.lastSyncAt, before, "but the sync time still moves")
        clock = clock.addingTimeInterval(31)
        await service.sync(records: [record(1), record(2), record(3)])
        XCTAssertEqual(seen.value.count, 3, "after 30 seconds it runs again")
    }

    func testRejectedKeepsTheLastSyncTimeAndReportsIt() async {
        _ = respond()
        let service = makeService()
        await service.sync(records: [record(1)])
        let good = service.lastSyncAt
        _ = respond(status: 401, json: #"{"error":"unauthorized"}"#)
        clock = clock.addingTimeInterval(60)
        await service.sync(records: [record(1), record(2)])
        XCTAssertEqual(service.lastError, .rejected)
        XCTAssertEqual(service.lastSyncAt, good)
    }

    func testOfflineAndRateLimitAreReported() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService()
        await service.sync(records: [record(1)])
        XCTAssertEqual(service.lastError, .offline)
        _ = respond(status: 429, json: #"{"error":"rate_limited"}"#)
        await service.sync(records: [record(1)], force: true)
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
        await service.sync(records: [record(1)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.path))
        service.turnOffAndForget()
        XCTAssertFalse(service.isPaired)
        XCTAssertFalse(service.enabled)
        XCTAssertNil(service.lastSyncAt)
        XCTAssertNil(MirrorSecretsStore(keychain: KeychainStore(account: account)).load())
        XCTAssertTrue(MirrorIndex(fileURL: indexFile).itemIDs(ofKind: "word").isEmpty)
        let count = seen.value.count
        await service.sync(records: [record(1)], force: true)
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
}
