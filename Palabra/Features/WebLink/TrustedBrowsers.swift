import Foundation

/// The computers this phone agreed to trust. Only a hash of each token is kept, so a copy of this list cannot be used to connect.
/// Pure value type: the controller saves it (Keychain) and the tests exercise every rule without a device.
struct TrustedBrowsers: Codable, Equatable, Sendable {
    static let maxCount = 8

    struct Entry: Codable, Equatable, Identifiable, Sendable {
        var id: String            // the browser's own id from the request
        var name: String
        var tokenHash: String
        var createdAt: Date
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Adds (or replaces, for the same browser id) a trusted computer. When the list is full the oldest one is dropped.
    mutating func trust(id: String, name: String, token: Data, now: Date) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, name: String(name.prefix(40)), tokenHash: TrustCrypto.tokenHash(token), createdAt: now))
        if entries.count > Self.maxCount { entries.removeFirst(entries.count - Self.maxCount) }
    }

    /// True when the token belongs to a computer in the list. Compares in constant time.
    func isTrusted(token: Data) -> Bool {
        guard token.count == TrustCrypto.tokenBytes else { return false }
        let hash = Array(TrustCrypto.tokenHash(token).utf8)
        var found = false
        for entry in entries {
            let other = Array(entry.tokenHash.utf8)
            guard other.count == hash.count else { continue }
            let same = zip(hash, other).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
            if same { found = true }
        }
        return found
    }

    mutating func remove(id: String) { entries.removeAll { $0.id == id } }
    mutating func removeAll() { entries.removeAll() }

    static func decode(_ text: String?) -> TrustedBrowsers {
        guard let data = text?.data(using: .utf8), let list = try? JSONDecoder.iso.decode(TrustedBrowsers.self, from: data) else { return TrustedBrowsers() }
        return list
    }

    func encoded() -> String {
        (try? JSONEncoder.iso.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

private extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
