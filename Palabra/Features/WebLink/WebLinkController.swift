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
    /// The "Trust this computer?" question on screen, if any. The view shows a confirmation for it.
    private(set) var trustQuestion: TrustRequests.Request?
    private(set) var trusted = TrustedBrowsers()

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
    @ObservationIgnored private let trustStore: KeychainStore
    @ObservationIgnored private var lobby: LobbyClient?
    @ObservationIgnored private var lobbyKeys: TrustCrypto.Keys?
    @ObservationIgnored private var lobbyDeviceId = ""
    @ObservationIgnored private var requests: TrustRequests?
    @ObservationIgnored private var gate = TrustGate()
    /// What the relay last said about the browser's seat. Remembered, because the relay's notice and the "connected" report travel
    /// on different callbacks and can arrive in either order: acting only on the notice as it passes would lose it when it came first.
    @ObservationIgnored private var presence = BrowserPresence()
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var stableTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var backoff = ReconnectBackoff()
    @ObservationIgnored private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    init(settings: WebLinkSettings = WebLinkSettings(),
         keychain: KeychainStore = .webLink(),
         trustStore: KeychainStore = .webTrust(),
         deviceName: String = UIDevice.current.name,
         clock: @escaping @Sendable () -> Date = { Date() },
         setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.settings = settings
        self.keychain = keychain
        self.trustStore = trustStore
        self.deviceName = deviceName
        self.clock = clock
        self.trusted = TrustedBrowsers.decode(trustStore.read())
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
        trustStore.delete()                  // trust is meaningless without the secret it was granted with
        trusted = TrustedBrowsers()
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
        openLobby()
        service.onPaired = { [weak self, keychain] secret in
            guard keychain.save(secret.hex) else { return false }
            Task { @MainActor in self?.pairingFinished() }
            return true
        }
        updateLocked()
    }

    func closePairing() {
        closeLobby()
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

    // MARK: Automatic pairing (the lobby)

    /// While "Pair a browser" is open the phone announces itself in the relay's lobby, so a browser on the same network can list it.
    /// Nothing is trusted until the person taps Trust; the announcement is a name and a one-time public key.
    private func openLobby() {
        closeLobby()
        guard settings.isEnabled, WebLinkSettings.isValidRelayURL(settings.relayURL), let client = LobbyClient(relayURL: settings.relayURL) else { return }
        let keys = TrustCrypto.Keys()
        lobbyKeys = keys
        lobbyDeviceId = LinkCrypto.randomBytes(16).hex
        requests = TrustRequests(deviceId: lobbyDeviceId, phonePub: keys.publicHex)
        client.onFrame = { [weak self] frame in Task { @MainActor in self?.lobbyFrame(frame) } }
        client.onState = { [weak self] state in Task { @MainActor in self?.lobbyStateChanged(state) } }
        lobby = client
        client.connect()
    }

    private func closeLobby() {
        announceTask?.cancel()
        announceTask = nil
        lobby?.onFrame = nil
        lobby?.onState = nil
        lobby?.send(["type": "gone", "deviceId": lobbyDeviceId])
        lobby?.disconnect()
        lobby = nil
        lobbyKeys = nil
        requests?.cancelAll()
        requests = nil
        trustQuestion = nil
    }

    private func lobbyStateChanged(_ state: LobbyClient.State) {
        switch state {
        case .connected: startAnnouncing()
        case .disconnected, .failed:
            announceTask?.cancel(); announceTask = nil
            if isPairingOpen, lobby != nil { reopenLobbySoon() }
        case .connecting: break
        }
    }

    private func reopenLobbySoon() {
        announceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { guard let self, self.isPairingOpen, !Task.isCancelled else { return }; self.lobby?.connect() }
        }
    }

    private func announce() {
        guard let keys = lobbyKeys else { return }
        lobby?.send(["type": "announce", "deviceId": lobbyDeviceId, "name": String(deviceName.prefix(40)), "pub": keys.publicHex])
    }

    private func startAnnouncing() {
        announceTask?.cancel()
        announce()
        announceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { guard let self, !Task.isCancelled else { return }; self.announce(); self.expireQuestions() }
            }
        }
    }

    private func lobbyFrame(_ frame: [String: Any]) {
        switch frame["type"] as? String {
        case "hello":
            announce()
        case "request":
            guard var current = requests else { return }
            let intake = current.receive(to: frame["to"] as? String, browserId: frame["browserId"] as? String,
                                         name: frame["name"] as? String, pub: frame["pub"] as? String, now: clock())
            requests = current
            if case .shown(let request) = intake { trustQuestion = request }
        default:
            break
        }
    }

    private func expireQuestions() {
        guard var current = requests else { return }
        if current.expire(now: clock()) { requests = current; trustQuestion = current.current }
    }

    /// The person tapped Trust (or Don't trust) on the question. Trust shares the link secret and a fresh token with that one
    /// computer only, remembers a hash of the token, and tells the page. Anything unexpected sends a decline, never a half grant.
    func answerTrust(accept: Bool) {
        guard var current = requests, let question = trustQuestion, let keys = lobbyKeys,
              let done = current.answer(browserId: question.browserId, now: clock()) else { trustQuestion = requests?.current; return }
        requests = current
        trustQuestion = done.next
        let id = done.answered.browserId
        func decline() { lobby?.send(["type": "decision", "browserId": id, "deviceId": lobbyDeviceId, "accepted": false]) }
        guard accept else { return decline() }
        guard let secret = currentOrNewSecret() else { return decline() }
        let token = LinkCrypto.randomBytes(TrustCrypto.tokenBytes)
        guard let box = try? TrustCrypto.sealGrant(phone: keys, browserPub: done.answered.browserPub, secret: secret, token: token,
                                                   relayURL: settings.relayURL) else { return decline() }
        var list = trusted
        list.trust(id: id, name: done.answered.name, token: token, now: clock())
        guard trustStore.save(list.encoded()) else { return decline() }   // never grant what could not be remembered
        trusted = list
        lobby?.send(["type": "decision", "browserId": id, "deviceId": lobbyDeviceId, "accepted": true, "iv": box.iv.hex, "sealed": box.sealed.hex])
        connect()
        refresh()
    }

    /// The secret already shared with paired browsers, or a new one when this is the first.
    private func currentOrNewSecret() -> Data? {
        if let hex = keychain.read(), let secret = Data(hexString: hex), secret.count == LinkCrypto.secretBytes { return secret }
        let secret = LinkCrypto.randomBytes(LinkCrypto.secretBytes)
        return keychain.save(secret.hex) ? secret : nil
    }

    /// Forget one trusted computer, or all of them. Every computer shares the one link secret, so the only way to really cut one
    /// off is to change the secret: the link is rebuilt on a new secret and the remaining computers are asked to trust again.
    /// (Their saved copy of the old secret no longer matches any room.) Removing everything is the same as "Forget This Browser".
    func revokeTrusted(id: String? = nil) {
        guard let id else { return revoke() }
        var list = trusted
        list.remove(id: id)
        let rotated = LinkCrypto.randomBytes(LinkCrypto.secretBytes)
        guard trustStore.save(TrustedBrowsers().encoded()), keychain.save(rotated.hex) else { return }
        trusted = TrustedBrowsers()          // the others hold the old secret: they must be trusted again
        disconnect()
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
        relay?.onPresence = nil
        relay?.disconnect()
        presence.relayLost()             // a replaced connection's browser notice must not carry over to the new one
        connectedRoom = client.roomIDValue
        connectedRelay = settings.relayURL
        let session = LinkCrypto.Session(secret: secret, role: .app)
        self.session = session
        gate.reset()
        client.onState = { [weak self] state in Task { @MainActor in self?.relayChanged(state) } }
        client.onFrame = { [weak self] frame in Task { @MainActor in self?.received(frame) } }
        client.onPresence = { [weak self] presence in Task { @MainActor in self?.presenceChanged(presence) } }
        relay = client
        client.connect()
    }

    private func disconnect() {
        stableTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        backoff.reset()
        relay?.onState = nil             // leaving on purpose is not a dropped connection
        relay?.onFrame = nil
        relay?.onPresence = nil
        relay?.disconnect()
        relay = nil
        connectedRoom = nil
        connectedRelay = nil
        relayIsUp = false
        presence.relayLost()             // whoever was in the old room says nothing about the next one
        session = nil
    }

    private func relayChanged(_ state: RelayClient.State) {
        relayIsUp = state == .connected
        switch state {
        case .failed, .disconnected: presence.relayLost()      // the connection that said it is over; the next one will say again
        case .connected: presence.relayConnected()
        case .connecting: break                                // never forget a notice that came ahead of this
        }
        switch state {
        case .connected:
            link = presence.link == .linked ? .linked : .waitingForBrowser   // the notice may already have arrived: never wait for what is already here
            // Only a connection that STAYS up earns a fresh start. Resetting at once would let two holders of one seat
            // replace each other as fast as they can connect.
            stableTask?.cancel()
            stableTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run { guard let self, !Task.isCancelled, self.relayIsUp else { return }; self.backoff.reset() }
            }
        case .failed(let message):
            // A dropped socket (Wi-Fi blip, iOS closing an idle connection, a connection that went quiet) heals on its own, or the
            // phone would wait for a browser forever. "Room full" came from an older relay without seats: retrying cannot help there.
            // "Replaced" (another holder of this phone's seat) takes the same path: the backoff spaces the tries out, so a stale
            // duplicate simply loses its seat back, and two live holders cannot fight faster than one try per 15 seconds.
            if message.hasPrefix("Another browser") { link = .failed(message) }
            else { link = settings.isEnabled ? .waitingForBrowser : .off; scheduleReconnect() }
        case .disconnected:
            link = settings.isEnabled ? .waitingForBrowser : .off
            if relay != nil { scheduleReconnect() }      // `relay` is nil when we disconnected on purpose
        case .connecting:
            link = settings.isEnabled ? .waitingForBrowser : .off
        }
    }

    /// The relay says whether the browser is in the room. It is the one source of truth for "waiting for the browser":
    /// a browser that arrives is `linked` at once, and one that leaves puts the phone back to waiting.
    private func presenceChanged(_ presence: RelayClient.Presence) {
        self.presence.notice(browserHere: presence == .here)
        guard relayIsUp else { return }                         // not connected yet: `.connected` will use what was remembered
        switch presence {
        case .here:
            if link == .waitingForBrowser { link = .linked }
        case .gone:
            if link == .linked { link = .waitingForBrowser }
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
        // A trusted computer says who it is first. A computer that was removed from the list is refused (and told, so its page
        // stops retrying); the others, and browsers paired with the code, are unaffected.
        if message.type == "hello" {
            // No token at all is a browser paired with the code. A token that cannot be read is NOT that: it is refused.
            let presented = message.payload?["token"]?.stringValue
            let token = presented.map { Data(hexString: $0) ?? Data() }      // an unreadable token becomes an empty one, which is never trusted
            let verdict = gate.hello(token: token, trusted: trusted)
            send(verdict == .allowed ? LinkMessage(id: message.id, type: "ack", version: 1, payload: .object([:]))
                                     : LinkMessage(id: message.id, type: "reject", version: 1, payload: .object(["reason": .string("revoked")])),
                 with: session)
            return
        }
        guard gate.verdict(trusted: trusted) == .allowed else {
            send(LinkMessage(id: message.id, type: "reject", version: 1, payload: .object(["reason": .string("revoked")])), with: session)
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
