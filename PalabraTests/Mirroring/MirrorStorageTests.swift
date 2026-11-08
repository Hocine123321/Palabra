import XCTest
@testable import Palabra

final class MirrorStorageTests: XCTestCase {
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "mirror-secrets-test-\(UUID().uuidString)"
    }

    override func tearDown() {
        KeychainStore(account: account).delete()
        super.tearDown()
    }

    private func sample() -> MirrorSecrets {
        MirrorSecrets(
            origin: "https://x.test", mirrorID: "MIR", ownerDeviceID: "own", ownerToken: "tok", dataKey: "KEY",
            computers: [MirrorComputer(id: "b1", name: "Home PC", pairedAt: Date(timeIntervalSince1970: 1_700_000_000))]
        )
    }

    func testSecretsRoundTripThroughTheKeychain() {
        let store = MirrorSecretsStore(keychain: KeychainStore(account: account))
        XCTAssertNil(store.load())
        XCTAssertTrue(store.save(sample()))
        XCTAssertEqual(store.load(), sample())
        XCTAssertEqual(store.load()?.bearer, "own.tok")
        store.clear()
        XCTAssertNil(store.load())
    }

    func testGarbageInTheKeychainLoadsAsNil() {
        let keychain = KeychainStore(account: account)
        XCTAssertTrue(keychain.save("this is not json"))
        XCTAssertNil(MirrorSecretsStore(keychain: keychain).load())
    }

    func testSettingsDecodeTolerantly() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(MirrorSettings.self, from: Data("{}".utf8)), MirrorSettings())
        XCTAssertTrue(try decoder.decode(MirrorSettings.self, from: Data(#"{"enabled":true}"#.utf8)).enabled)
        let extra = try decoder.decode(MirrorSettings.self, from: Data(#"{"enabled":true,"futureField":[1,2],"lastSyncAt":5}"#.utf8))
        XCTAssertTrue(extra.enabled)
        XCTAssertNotNil(extra.lastSyncAt)
    }

    func testSettingsStorePersists() throws {
        let suite = "mirror-settings-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MirrorSettingsStore(defaults: defaults)
        XCTAssertEqual(store.value, MirrorSettings())
        store.value = MirrorSettings(enabled: true, lastSyncAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(MirrorSettingsStore(defaults: defaults).value.enabled, true)
        XCTAssertNotNil(defaults.data(forKey: "mirrorSettings"))
    }
}
