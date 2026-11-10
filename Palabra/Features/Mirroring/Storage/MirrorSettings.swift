import Foundation

/// The non-secret Mirroring settings (UserDefaults key `mirrorSettings`). The decoder is tolerant: every field is optional
/// and unknown fields are ignored, so adding a field never loses what is stored.
struct MirrorSettings: Codable, Equatable {
    var enabled: Bool = false
    var lastSyncAt: Date?
    /// When the last manifest went out, and the id hash it carried (decides when the next one is due).
    var lastManifestAt: Date?
    var lastManifestIDsHash: String?

    init(enabled: Bool = false, lastSyncAt: Date? = nil) {
        self.enabled = enabled
        self.lastSyncAt = lastSyncAt
    }

    private enum CodingKeys: String, CodingKey { case enabled, lastSyncAt, lastManifestAt, lastManifestIDsHash }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastManifestAt = try container.decodeIfPresent(Date.self, forKey: .lastManifestAt)
        lastManifestIDsHash = try container.decodeIfPresent(String.self, forKey: .lastManifestIDsHash)
    }
}

final class MirrorSettingsStore {
    static let key = "mirrorSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var value: MirrorSettings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(MirrorSettings.self, from: data) else { return MirrorSettings() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Self.key) }
        }
    }
}
