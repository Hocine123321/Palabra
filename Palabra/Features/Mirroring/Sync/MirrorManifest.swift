import CryptoKit
import Foundation

/// The manifest: one sealed item pushed after the data items. It lists how many items of each kind exist and a hash of
/// all their ids, so the browser can tell a complete copy from a partial one (docs/features/mirroring.md, Protocol v1).
enum MirrorManifest {
    static let kind = "manifest"
    static let recordID = "manifest"
    /// A manifest is pushed at least this often (seconds) so the page can show when the phone last checked in.
    static let heartbeat: TimeInterval = 600

    /// Lowercase hex SHA-256 of the ids sorted by code point and joined with a newline. Item ids are ASCII (base64url).
    static func idsHash(_ ids: [String]) -> String {
        let text = ids.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func record(ids: [String], counts: [String: Int], now: Date) -> MirrorRecord {
        let payload: JSONValue = .object([
            "counts": .object(counts.mapValues { JSONValue.number(Double($0)) }),
            "idsHash": .string(idsHash(ids)),
            "pushedAt": .string(ISO8601DateFormatter().string(from: now)),
        ])
        return MirrorRecord(kind: kind, recordID: recordID, payload: payload)
    }
}
