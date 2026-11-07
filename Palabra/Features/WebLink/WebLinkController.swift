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
    @ObservationIgnored private var relayIsUp = false      // true only between the socket opening and closing
    @ObservationIgnored private var connectedRoom: String?
    @ObservationIgnored private var connectedRelay: String?
    /// Set by the app once the capability registry exists. Without it the link only answers `ping`.
    @ObservationIgnored var dispatcher: WebLinkDispatcher?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var backoff = ReconnectBackoff()
    @ObservationIgnored private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    init(settings: WebLinkSettings = WebLinkSettings(),
         keychain: KeychainStore = .webLink(),
         setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.settings = settings
        self.keychain = keychain
        self.setIdleTimerDisabled = setIdleTimerDisabled
        let store = settings
        self.service = PairingService(lockout: settings.lockout, persist: { store.lockout = $0 })
        self.service.relayURL = { store.relayURL }
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
        if active { connect() } else { disconnect() }
        refresh()
    }

    // MARK: Relay

    private func connect() {
        guard settings.isEnabled, appActive, let hex = keychain.read(), let secret = Data(hexString: hex),
              let client = RelayClient(relayURL: settings.relayURL, roomID: LinkCrypto.roomID(secret: secret)) else { return }
        // Already connected to this very room: leave it alone. Rebuilding would kick the browser off for nothing
        // (the scene phase flips to active for many small reasons).
        if relay != nil, relayIsUp, connectedRoom == client.roomIDValue, connectedRelay == settings.relayURL { return }
        relay?.onState = nil             // the old client's goodbye must not look like a dropped connection
        relay?.onFrame = nil
        relay?.disconnect()
        connectedRoom = client.roomIDValue
        connectedRelay = settings.relayURL
        let session = LinkCrypto.Session(secret: secret, role: .app)
        self.session = session
        client.onState = { [weak self] state in Task { @MainActor in self?.relayChanged(state) } }
        client.onFrame = { [weak self] frame in Task { @MainActor in self?.received(frame) } }
        relay = client
        client.connect()
    }

    private func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        backoff.reset()
        relay?.onState = nil             // leaving on purpose is not a dropped connection
        relay?.onFrame = nil
        relay?.disconnect()
        relay = nil
        connectedRoom = nil
        connectedRelay = nil
        relayIsUp = false
        session = nil
    }

    private func relayChanged(_ state: RelayClient.State) {
        relayIsUp = state == .connected
        switch state {
        case .connected:
            link = .waitingForBrowser
            backoff.reset()
        case .failed(let message):
            link = .failed(message)
            // "Room full" means another browser really holds the link: retrying would not help. Anything else is a dropped socket
            // (Wi-Fi blip, iOS closing an idle connection) and must heal on its own, or the phone waits for a browser forever.
            if !message.hasPrefix("Another browser") { scheduleReconnect() }
        case .disconnected:
            link = settings.isEnabled ? .waitingForBrowser : .off
            if relay != nil { scheduleReconnect() }      // `relay` is nil when we disconnected on purpose
        case .connecting:
            link = settings.isEnabled ? .waitingForBrowser : .off
        }
    }

    /// Tries again after 1, 2, 4, 8, then every 15 seconds, only while the app is in front and Web Access is on.
    /// A newer connection (or leaving the foreground) cancels a pending try, so tries never pile up.
    private func scheduleReconnect() {
        guard settings.isEnabled, appActive, keychain.read() != nil else { return }
        reconnectTask?.cancel()
        let delay = backoff.next()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.appActive, self.settings.isEnabled, !self.relayIsUp else { return }
                self.connect()
            }
        }
    }

    /// `ping` is answered here; `read` and `snapshot` go to the dispatcher (read-only). Anything unreadable is dropped
    /// silently, and unknown types are ignored so old files and new apps keep working.
    private func received(_ frame: Data) {
        guard let session, let plain = try? session.open(frame),
              let message = try? JSONDecoder().decode(LinkMessage.self, from: plain) else { return }
        link = .linked
        if message.type == "ping" {
            send(LinkMessage(id: message.id, type: "ack", version: 1, payload: message.payload), with: session)
            return
        }
        guard let dispatcher else {
            send(LinkMessage(id: message.id, type: "reject", version: 1, payload: .object(["reason": .string("failed")])), with: session)
            return
        }
        Task { [weak self] in
            guard let reply = await dispatcher.handle(message) else { return }
            await MainActor.run { self?.send(reply, with: session) }
        }
    }

    /// Seals and sends a reply, split into pieces when it would not fit one relay frame.
    /// Replies for a session that has since been replaced (unpaired, reconnected) are dropped.
    /// A reply that cannot be built or sealed is never dropped silently: the page gets a `reject` with a reason instead,
    /// because silence is indistinguishable from a phone that is away.
    private func send(_ reply: LinkMessage, with sessionAtRequest: LinkCrypto.Session) {
        guard session === sessionAtRequest else { return }
        if deliver(reply, with: sessionAtRequest) { return }
        let refusal = LinkMessage(id: reply.id, type: "reject", version: 1, payload: .object(["reason": .string("failed")]))
        _ = deliver(refusal, with: sessionAtRequest)
    }

    /// True when every piece was sealed and handed to the relay.
    private func deliver(_ reply: LinkMessage, with session: LinkCrypto.Session) -> Bool {
        guard let pieces = try? LinkChunking.pieces(of: reply) else { return false }
        var frames: [Data] = []
        for piece in pieces {
            guard let data = try? JSONEncoder().encode(piece), let sealed = try? session.seal(data) else { return false }
            frames.append(sealed)
        }
        for frame in frames { relay?.send(frame) }
        return true
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
