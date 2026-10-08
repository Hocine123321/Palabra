import Foundation

enum CapabilityLimits {
    static let maxArgsBytes = 65_536
}

/// The single door between an artifact and the app.
struct CapabilityRegistry: Sendable {
    private let byName: [String: Capability]

    /// Later duplicates of a name replace earlier ones.
    init(_ capabilities: [Capability]) {
        var map: [String: Capability] = [:]
        for capability in capabilities { map[capability.name] = capability }
        byName = map
    }

    var all: [Capability] { byName.values.sorted { $0.name < $1.name } }

    func capability(named name: String) -> Capability? { byName[name] }

    /// Order: unknown -> not granted (`.local` exempt) -> args too big -> dry-run write -> handler.
    func call(name: String, args: JSONValue, session: ArtifactSession, granted: Set<String>) async -> Result<JSONValue, CapabilityError> {
        guard let capability = byName[name] else { return .failure(.unknown) }
        guard capability.kind == .local || granted.contains(name) else { return .failure(.notGranted) }
        guard args.jsonString.utf8.count <= CapabilityLimits.maxArgsBytes else {
            return .failure(.badArgs("arguments too large"))
        }
        if session.dryRun && capability.kind == .write {
            return .success(capability.dryRunValue ?? .object([:]))
        }
        return await capability.handler(args, session)
    }

    /// The AI-facing manual: one block per capability.
    func manual(including classes: Set<CapabilityClass> = [.read, .write, .ai, .local]) -> String {
        all.filter { classes.contains($0.kind) }.map { capability in
            """
            - \(capability.name) (\(capability.kind.label)): \(capability.summary)
              args: \(capability.argsSchema.jsonString)
              returns: \(capability.returnsSummary)
            """
        }.joined(separator: "\n")
    }
}
