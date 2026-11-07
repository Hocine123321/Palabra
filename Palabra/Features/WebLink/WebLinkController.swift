import Foundation
import Observation
import UIKit

/// Owns the web link on the phone: the switch, pairing, the relay connection and the keep-awake rule.
/// Phase 1 only answers an encrypted `ping` with an `ack`; reading and writing app data comes in later phases
/// through the capability registry.
@MainActor
@Observable
final class WebLinkController {
    enum Link: Equatable {
        case off
        case waitingForBrowser        // switched on, paired, relay connecting or the browser not here yet
        case linked
        case failed(String)
        case needsPairing
    }

    private(set) var link: Link = .off
    private(set) var pairingCode: String?
    private(set) var isPairingOpen = false
    private(set) var pairingError: String?
    private(set) var lockedSeconds = 0

    @ObservationIgnored private var settings: WebLinkSettings
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let service: PairingService
    @ObservationIgnored private let listener: LocalPairingListener
    @ObservationIgnored private var relay: RelayClient?
    @ObservationIgnored private var session: LinkCrypto.Session?
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    init(settings: WebLinkSettings = WebLinkSettings(),
         keychain: KeychainStore = .webLink(),
         setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.settings = settings
        self.keychain = keychain
        self.setIdleTimerDisabled = setIdleTimerDisabled
        let store = settings
        self.service = PairingService(lockout: settings.lockout, persist: { store.lockout = $0 })
        self.listener = LocalPairingListener(service: service)
        refresh()
    }

    var isEnabled: Bool { settings.isEnabled }
    var relayURL: String { settings.relayURL }
    var isPaired: Bool { keychain.read() != nil }

    // MARK: Switch

    func setEnabled(_ on: Bool) {
        settings.isEnabled = on
        if !on { closePairing(); disconnect() }
        refresh()
    }

    func setRelayURL(_ text: String) -> Bool {
        guard WebLinkSettings.isValidRelayURL(text) else { return false }
        settings.relayURL = text
        refresh()
        return true
    }

    /// Forget the paired browser: the secret is deleted, so the old page can never reconnect.
    func revoke() {
        keychain.delete()
        disconnect()
        refresh()
    }

    // MARK: Pairing

    /// Opens the local listener with a code the person chose. The code is shown only while this is open.
    func openPairing(code: String) {
        pairingError = nil
        guard settings.isEnabled else { pairingError = "Switch Web Access on first."; return }
        guard service.open(code: code) else { pairingError = "Use at least 6 digits."; return }
        do { try listener.start() } catch { pairingError = "Could not start on this network."; return }
        pairingCode = code
        isPairingOpen = true
        service.onPaired = { [weak self, keychain] secret in
            guard keychain.save(secret.hex) else { return false }
            Task { @MainActor in self?.pairingFinished() }
            return true
        }
        updateLocked()
    }

    func closePairing() {
        listener.stop()
        service.close()
        pairingCode = nil
        isPairingOpen = false
    }

    func updateLocked() {
        lockedSeconds = Int(service.currentLockout.remaining(now: Date()).rounded(.up))
    }

    private func pairingFinished() {
        closePairing()
        connect()
        refresh()
    }

    // MARK: Foreground rule

    func appBecameActive(_ active: Bool) {
        appActive = active
        if active { connect() } else { relay?.disconnect(); relay = nil }
        refresh()
    }

    // MARK: Relay

    private func connect() {
        guard settings.isEnabled, appActive, let hex = keychain.read(), let secret = Data(hexString: hex),
              let client = RelayClient(relayURL: settings.relayURL, roomID: LinkCrypto.roomID(secret: secret)) else { return }
        relay?.disconnect()
        let session = LinkCrypto.Session(secret: secret, role: .app)
        self.session = session
        client.onState = { [weak self] state in Task { @MainActor in self?.relayChanged(state) } }
        client.onFrame = { [weak self] frame in Task { @MainActor in self?.received(frame) } }
        relay = client
        client.connect()
    }

    private func disconnect() {
        relay?.disconnect()
        relay = nil
        session = nil
    }

    private func relayChanged(_ state: RelayClient.State) {
        switch state {
        case .connected: link = .waitingForBrowser
        case .failed(let message): link = .failed(message)
        case .connecting, .disconnected: link = settings.isEnabled ? .waitingForBrowser : .off
        }
    }

    /// Phase 1: the only message is `ping`, answered with `ack`. Anything unreadable is dropped silently.
    private func received(_ frame: Data) {
        guard let session, let plain = try? session.open(frame),
              let message = try? JSONDecoder().decode(LinkMessage.self, from: plain) else { return }
        link = .linked
        guard message.type == "ping" else { return } // unknown types are ignored so old files and new apps keep working
        let reply = LinkMessage(id: message.id, type: "ack", version: 1, payload: message.payload)
        if let data = try? JSONEncoder().encode(reply), let sealed = try? session.seal(data) { relay?.send(sealed) }
    }

    // MARK: State

    private func refresh() {
        setIdleTimerDisabled(KeepAwake.shouldDisableIdleTimer(featureOn: settings.isEnabled, appActive: appActive))
        if !settings.isEnabled { link = .off }
        else if !isPaired { link = .needsPairing }
        else if case .failed = link {} else if link == .off || link == .needsPairing { link = .waitingForBrowser }
    }
}

/// The envelope of every message: `{id, type, version, payload}`, encrypted as a whole.
struct LinkMessage: Codable, Equatable {
    var id: String
    var type: String
    var version: Int
    var payload: JSONValue?
}
