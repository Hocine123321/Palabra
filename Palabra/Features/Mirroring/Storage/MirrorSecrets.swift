import Foundation

/// A paired browser, as the phone remembers it. The name is the person's label ("Home PC").
struct MirrorComputer: Codable, Equatable, Identifiable {
    let id: String // the device id the Worker knows it by
    var name: String
    let pairedAt: Date
    /// base64url, 32 bytes: how the phone seals a new data key to this computer. nil for a computer paired before key rotation existed.
    var deviceKey: String?

    init(id: String, name: String, pairedAt: Date, deviceKey: String? = nil) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.deviceKey = deviceKey
    }

    private enum CodingKeys: String, CodingKey { case id, name, pairedAt, deviceKey }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pairedAt = try c.decode(Date.self, forKey: .pairedAt)
        deviceKey = try c.decodeIfPresent(String.self, forKey: .deviceKey)
    }
}

/// Everything secret about this phone's mirror. Lives in the Keychain only (account `mirror-secrets`), never in a file,
/// UserDefaults, a log or an error message.
struct MirrorSecrets: Codable, Equatable {
    var origin: String
    var mirrorID: String
    var ownerDeviceID: String
    var ownerToken: String
    var dataKey: String // base64url, 32 bytes
    var computers: [MirrorComputer]
    /// Which data key generation `dataKey` is. A mirror starts at 0; every rotation adds one.
    var epoch: Int
    /// A new key the phone made for a rotation and has not seen confirmed yet. Saved before the Worker is called, so a crash
    /// in between never leaves stored data sealed under a key nobody holds. See `MirrorService.promotePendingIfNeeded`.
    var pending: Pending?

    struct Pending: Codable, Equatable {
        var dataKey: String
        var epoch: Int
        /// The computers the rotation removes (the one the person chose, and those that could not be given the new key).
        var removedIDs: [String]

        init(dataKey: String, epoch: Int, removedIDs: [String] = []) {
            self.dataKey = dataKey
            self.epoch = epoch
            self.removedIDs = removedIDs
        }

        private enum CodingKeys: String, CodingKey { case dataKey, epoch, removedIDs }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dataKey = try c.decode(String.self, forKey: .dataKey)
            epoch = try c.decode(Int.self, forKey: .epoch)
            removedIDs = try c.decodeIfPresent([String].self, forKey: .removedIDs) ?? []
        }
    }

    init(origin: String, mirrorID: String, ownerDeviceID: String, ownerToken: String, dataKey: String, computers: [MirrorComputer], epoch: Int = 0, pending: Pending? = nil) {
        self.origin = origin
        self.mirrorID = mirrorID
        self.ownerDeviceID = ownerDeviceID
        self.ownerToken = ownerToken
        self.dataKey = dataKey
        self.computers = computers
        self.epoch = epoch
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey { case origin, mirrorID, ownerDeviceID, ownerToken, dataKey, computers, epoch, pending }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decode(String.self, forKey: .origin)
        mirrorID = try c.decode(String.self, forKey: .mirrorID)
        ownerDeviceID = try c.decode(String.self, forKey: .ownerDeviceID)
        ownerToken = try c.decode(String.self, forKey: .ownerToken)
        dataKey = try c.decode(String.self, forKey: .dataKey)
        computers = try c.decode([MirrorComputer].self, forKey: .computers)
        epoch = try c.decodeIfPresent(Int.self, forKey: .epoch) ?? 0
        pending = try c.decodeIfPresent(Pending.self, forKey: .pending)
    }

    var bearer: String { ownerDeviceID + "." + ownerToken }
}

struct MirrorSecretsStore {
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore(account: "mirror-secrets")) { self.keychain = keychain }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// nil when nothing is stored, or when the stored value is not readable.
    func load() -> MirrorSecrets? {
        guard let text = keychain.read(), let data = text.data(using: .utf8) else { return nil }
        return try? Self.decoder().decode(MirrorSecrets.self, from: data)
    }

    @discardableResult
    func save(_ secrets: MirrorSecrets) -> Bool {
        guard let data = try? Self.encoder().encode(secrets), let text = String(data: data, encoding: .utf8) else { return false }
        return keychain.save(text)
    }

    func clear() { keychain.delete() }
}
