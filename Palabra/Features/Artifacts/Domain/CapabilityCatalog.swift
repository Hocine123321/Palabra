import Foundation

/// What the Capabilities screen shows: which capabilities each kind of artifact may use and what the person is asked about.
/// Built from `GrantPolicy` and the live registry, so the screen cannot disagree with the rules the app really enforces.
enum CapabilityCatalog {
    /// How the person is asked about a capability for one kind of artifact.
    enum Access: Equatable, Sendable {
        /// Never asked: the artifact's own storage, or a read that a page may bind to.
        case automatic
        /// The person approves it once, in the preview, before the app can use it.
        case askFirst
        /// This kind of artifact cannot use it at all.
        case unavailable
    }

    struct Entry: Equatable, Sendable {
        let name: String
        let kind: CapabilityClass
        let summary: String
        /// Argument name and plain description, sorted by name.
        let arguments: [(name: String, detail: String)]
        let returns: String
        let access: Access

        static func == (a: Entry, b: Entry) -> Bool {
            a.name == b.name && a.kind == b.kind && a.access == b.access && a.summary == b.summary && a.returns == b.returns
                && a.arguments.map(\.name) == b.arguments.map(\.name)
        }
    }

    /// The capabilities an artifact of `kind` can use, in the order the screen lists them (reads, writes, AI, own storage; by name).
    /// A page only shows data, so it can bind to reads and nothing else; an interactive app may use every capability.
    static func entries(for kind: ArtifactKind, registry: CapabilityRegistry) -> [Entry] {
        registry.all.compactMap { capability -> Entry? in
            let access = self.access(of: capability, for: kind)
            guard access != .unavailable else { return nil }
            return Entry(
                name: capability.name, kind: capability.kind, summary: capability.summary,
                arguments: arguments(of: capability), returns: capability.returnsSummary, access: access
            )
        }
        .sorted { (order($0.kind), $0.name) < (order($1.kind), $1.name) }
    }

    /// The capabilities the AI is told about for `kind` (the same filter the prompt uses).
    static func access(of capability: Capability, for kind: ArtifactKind) -> Access {
        switch kind {
        case .spec:
            // A page binds to reads only (`SpecValidator`); anything else is dropped from it.
            return capability.kind == .read || capability.kind == .local ? .automatic : .unavailable
        case .app:
            return GrantPolicy.autoGranted(kind: .app, capability: capability) ? .automatic : .askFirst
        }
    }

    static func arguments(of capability: Capability) -> [(name: String, detail: String)] {
        guard case .object(let fields) = capability.argsSchema else { return [] }
        return fields.keys.sorted().map { key in
            if case .string(let text) = fields[key] { return (key, text) }
            return (key, fields[key]?.jsonString ?? "")
        }
    }

    /// Reads first (they are the safest), then writes, then the AI, then the artifact's own storage.
    private static func order(_ kind: CapabilityClass) -> Int {
        switch kind {
        case .read: return 0
        case .write: return 1
        case .ai: return 2
        case .local: return 3
        }
    }
}
