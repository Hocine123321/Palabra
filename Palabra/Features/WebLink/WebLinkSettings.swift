import Foundation

/// The web link's own settings. Every key here is new (the frozen names in AGENTS.md are untouched).
struct WebLinkSettings {
    private enum Keys {
        static let enabled = "webLinkEnabled"
        static let relayURL = "webLinkRelayURL"
        static let lockout = "webLinkLockout"
    }

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// The person's own Cloudflare Worker, for example `wss://palabra-relay.example.workers.dev`.
    var relayURL: String {
        get { defaults.string(forKey: Keys.relayURL) ?? "" }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.relayURL) }
    }

    var lockout: PairingLockout {
        get { defaults.data(forKey: Keys.lockout).flatMap { try? JSONDecoder().decode(PairingLockout.self, from: $0) } ?? PairingLockout() }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.lockout) }
    }

    /// Only a secure relay address is accepted (plain `ws://` only for a relay on this network while developing).
    static func isValidRelayURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.path.isEmpty || url.path == "/" else { return false }
        if url.scheme == "wss" { return true }
        return url.scheme == "ws" && (host == "localhost" || PrivateAddress.isPrivate(ipv4: ipv4Bytes(host) ?? Data()))
    }

    private static func ipv4Bytes(_ host: String) -> Data? {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        return parts.count == 4 ? Data(parts) : nil
    }
}

/// When the screen must stay awake: only while the feature is switched on and the app is in the foreground.
/// Pure, so the rule is tested (`isIdleTimerDisabled` itself is set by `WebLinkController`).
enum KeepAwake {
    static func shouldDisableIdleTimer(featureOn: Bool, appActive: Bool) -> Bool { featureOn && appActive }
}
