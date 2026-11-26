import Foundation

/// How big an artifact is, and (like a commit) how much a change added and removed. Lines are counted on what a person
/// would read: an HTML page as it is, a table-style artifact (compact JSON) pretty-printed so it has lines at all.
struct ArtifactSize: Equatable {
    var lines: Int
    var bytes: Int
}

struct ArtifactChange: Equatable {
    var added: Int
    var removed: Int
    var isEmpty: Bool { added == 0 && removed == 0 }
}

enum ArtifactMetrics {
    /// Above this many lines on either side the exact diff is skipped (it is a picture, not an audit), and the change is
    /// the difference in length.
    static let exactDiffLimit = 6_000

    static func size(of payload: Data, kind: ArtifactKind) -> ArtifactSize {
        ArtifactSize(lines: lines(of: payload, kind: kind).count, bytes: payload.count)
    }

    /// `old` is nil when there is nothing to compare with (a first draft): no change is shown then.
    static func change(from old: Data?, to new: Data, kind: ArtifactKind) -> ArtifactChange? {
        guard let old else { return nil }
        let before = lines(of: old, kind: kind)
        let after = lines(of: new, kind: kind)
        if before.count > exactDiffLimit || after.count > exactDiffLimit {
            let delta = after.count - before.count
            return ArtifactChange(added: max(delta, 0), removed: max(-delta, 0))
        }
        let difference = after.difference(from: before)
        var added = 0
        var removed = 0
        for step in difference {
            switch step {
            case .insert: added += 1
            case .remove: removed += 1
            }
        }
        return ArtifactChange(added: added, removed: removed)
    }

    /// The lines a reader sees. An empty payload has none.
    static func lines(of payload: Data, kind: ArtifactKind) -> [String] {
        var text = String(decoding: payload, as: UTF8.self)
        if kind == .spec,
           let object = try? JSONSerialization.jsonObject(with: payload),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            text = String(decoding: pretty, as: UTF8.self)
        }
        guard !text.isEmpty else { return [] }
        var parts = text.components(separatedBy: "\n")
        // A trailing newline is not another line.
        if parts.last == "" { parts.removeLast() }
        return parts
    }
}
