import XCTest
@testable import Palabra

final class WebLinkSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "weblink-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    func testDefaultsAreOffAndEmpty() {
        let s = WebLinkSettings(defaults: defaults())
        XCTAssertFalse(s.isEnabled)
        XCTAssertEqual(s.relayURL, "")
        XCTAssertEqual(s.lockout, PairingLockout())
    }

    func testValuesPersist() {
        let d = defaults()
        let s = WebLinkSettings(defaults: d)
        s.isEnabled = true
        s.relayURL = "  wss://relay.example.workers.dev  "
        var l = PairingLockout(); for _ in 0..<5 { l.recordWrong(now: Date(timeIntervalSince1970: 5)) }
        s.lockout = l
        let again = WebLinkSettings(defaults: d)
        XCTAssertTrue(again.isEnabled)
        XCTAssertEqual(again.relayURL, "wss://relay.example.workers.dev")
        XCTAssertEqual(again.lockout, l)
    }

    func testRelayAddressRules() {
        XCTAssertTrue(WebLinkSettings.isValidRelayURL("wss://palabra-relay.me.workers.dev"))
        XCTAssertTrue(WebLinkSettings.isValidRelayURL("wss://palabra-relay.me.workers.dev/"))
        XCTAssertFalse(WebLinkSettings.isValidRelayURL("ws://palabra-relay.me.workers.dev"))   // plain ws only on this network
        XCTAssertTrue(WebLinkSettings.isValidRelayURL("ws://192.168.1.20"))
        XCTAssertTrue(WebLinkSettings.isValidRelayURL("ws://localhost"))
        XCTAssertFalse(WebLinkSettings.isValidRelayURL("https://example.com"))
        XCTAssertFalse(WebLinkSettings.isValidRelayURL("wss://example.com/r/abc"))
        XCTAssertFalse(WebLinkSettings.isValidRelayURL("wss://"))
        XCTAssertFalse(WebLinkSettings.isValidRelayURL(""))
    }

    func testKeepAwakeOnlyWhileOnAndForeground() {
        XCTAssertTrue(KeepAwake.shouldDisableIdleTimer(featureOn: true, appActive: true))
        XCTAssertFalse(KeepAwake.shouldDisableIdleTimer(featureOn: true, appActive: false))
        XCTAssertFalse(KeepAwake.shouldDisableIdleTimer(featureOn: false, appActive: true))
        XCTAssertFalse(KeepAwake.shouldDisableIdleTimer(featureOn: false, appActive: false))
    }

    func testNewNamesDoNotTouchFrozenOnes() {
        // The web link only adds keys and a Keychain slot; the API key slots are unchanged.
        let d = defaults()
        d.set("gemini-x", forKey: "selectedModelID")
        let s = WebLinkSettings(defaults: d); s.isEnabled = true
        XCTAssertEqual(d.string(forKey: "selectedModelID"), "gemini-x")
    }

    func testLinkMessageEnvelopeRoundTripsAndIgnoresUnknownFields() throws {
        let json = #"{"id":"1","type":"ping","version":1,"payload":{"n":1},"future":true}"#
        let m = try JSONDecoder().decode(LinkMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.type, "ping")
        XCTAssertEqual(try JSONDecoder().decode(LinkMessage.self, from: JSONEncoder().encode(m)), m)
    }
}

@MainActor
final class WebLinkControllerTests: XCTestCase {
    private func make(idle: @escaping @MainActor (Bool) -> Void = { _ in }) -> (WebLinkController, UserDefaults) {
        let suite = "weblink-ctl-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        let keychain = KeychainStore(account: "web-link-secret-test-\(UUID().uuidString)")
        addTeardownBlock { keychain.delete() }
        return (WebLinkController(settings: WebLinkSettings(defaults: d), keychain: keychain, setIdleTimerDisabled: idle), d)
    }

    func testSwitchingOnKeepsAwakeAndOffReleasesIt() {
        var awake = false
        let (web, _) = make { awake = $0 }
        XCTAssertFalse(awake)
        web.setEnabled(true)
        XCTAssertTrue(awake)
        XCTAssertEqual(web.link, .needsPairing)
        web.appBecameActive(false)
        XCTAssertFalse(awake)                       // backgrounded: released
        web.appBecameActive(true)
        XCTAssertTrue(awake)
        web.setEnabled(false)
        XCTAssertFalse(awake)
        XCTAssertEqual(web.link, .off)
    }

    func testPairingNeedsTheSwitchAndAGoodCode() {
        let (web, _) = make()
        web.openPairing(code: "482913")
        XCTAssertFalse(web.isPairingOpen)
        XCTAssertNotNil(web.pairingError)
        web.setEnabled(true)
        web.openPairing(code: "123")
        XCTAssertFalse(web.isPairingOpen)
        XCTAssertEqual(web.pairingError, "Use at least 6 digits.")
    }

    func testRelayAddressIsValidatedBeforeItIsSaved() {
        let (web, _) = make()
        XCTAssertFalse(web.setRelayURL("http://nope"))
        XCTAssertEqual(web.relayURL, "")
        XCTAssertTrue(web.setRelayURL("wss://r.example.workers.dev"))
        XCTAssertEqual(web.relayURL, "wss://r.example.workers.dev")
    }
}
