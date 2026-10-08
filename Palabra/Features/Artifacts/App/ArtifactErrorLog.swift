import Foundation
import Observation

/// Runtime errors from one open app artifact (script errors, rejected calls). In memory only; feeds "Fix with AI".
@MainActor
@Observable
final class ArtifactErrorLog {
    static let maxEntries = 20
    static let maxEntryLength = 300

    private(set) var entries: [String] = []

    func append(_ text: String) {
        entries.append(String(text.prefix(Self.maxEntryLength)))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    func clear() { entries = [] }

    var summary: String { entries.joined(separator: "\n") }
}
