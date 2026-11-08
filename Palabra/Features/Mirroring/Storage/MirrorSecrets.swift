import Foundation

/// A paired browser, as the phone remembers it. The name is the person's label ("Home PC").
struct MirrorComputer: Codable, Equatable, Identifiable {
    let id: String // the device id the Worker knows it by
    var name: String
    let pairedAt: Date
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
