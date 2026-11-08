import CryptoKit
import Foundation

/// One thing the phone mirrors: a kind ("word"), the phone's own id for it and its content as plain JSON.
/// `Features/Mirroring` never sees an app model; `App/AppEnvironment+Mirror.swift` builds these.
struct MirrorRecord: Equatable, Sendable {
    let kind: String
    let recordID: String
    let payload: JSONValue

    /// SHA-256 hex of the payload as sorted-key JSON, so the same content hashes the same however it was built.
    var contentHash: String {
        SHA256.hash(data: Data(payload.jsonString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
