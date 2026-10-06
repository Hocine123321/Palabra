import Foundation

/// Who needs approval. Spec artifacts only ever bind reads, so they never prompt;
/// app artifacts need approval for everything except their own storage.
enum GrantPolicy {
    static func autoGranted(kind: ArtifactKind, capability: Capability) -> Bool {
        capability.kind == .local || (capability.kind == .read && kind == .spec)
    }

    /// Requested capabilities that exist and still need the user's approval (sorted, unique).
    static func needingApproval(kind: ArtifactKind, requested: [String], registry: CapabilityRegistry) -> [Capability] {
        Set(requested).compactMap { registry.capability(named: $0) }
            .filter { !autoGranted(kind: kind, capability: $0) }
            .sorted { $0.name < $1.name }
    }

    /// requested ∩ (granted ∪ auto-granted); unknown names are dropped.
    static func effectiveGrant(kind: ArtifactKind, requested: [String], granted: Set<String>, registry: CapabilityRegistry) -> Set<String> {
        Set(requested.compactMap { name -> String? in
            guard let capability = registry.capability(named: name) else { return nil }
            return autoGranted(kind: kind, capability: capability) || granted.contains(name) ? name : nil
        })
    }
}
