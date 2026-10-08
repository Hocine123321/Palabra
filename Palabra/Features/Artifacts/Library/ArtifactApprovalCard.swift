import SwiftUI

/// Who may use what. App artifacts need approval for everything except their own storage;
/// the decision is made once, in the preview, and stored on Save.
enum ArtifactApproval {
    /// Requested capabilities that exist, are not auto-granted for this kind, and are not granted yet (sorted by name).
    static func pending(kind: ArtifactKind, requested: [String], granted: Set<String>, registry: CapabilityRegistry) -> [Capability] {
        GrantPolicy.needingApproval(kind: kind, requested: requested, registry: registry).filter { !granted.contains($0.name) }
    }

    /// requested ∩ (granted ∪ auto-granted). A denied capability is simply absent, so its calls return `notGranted`.
    static func effective(kind: ArtifactKind, requested: [String], granted: Set<String>, registry: CapabilityRegistry) -> Set<String> {
        GrantPolicy.effectiveGrant(kind: kind, requested: requested, granted: granted, registry: registry)
    }
}

/// Plain-language approval, shown before an app artifact can do anything.
struct ArtifactApprovalCard: View {
    let capabilities: [Capability]
    var onAllow: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This artifact wants to")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.ink)
            ForEach(Array(capabilities.enumerated()), id: \.offset) { _, capability in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Self.label(capability.kind)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    Text(verbatim: capability.summary).font(.subheadline).foregroundStyle(Theme.ink)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button("Not now", action: onDeny)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("denyArtifactButton")
                Button("Allow", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("allowArtifactButton")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private static func label(_ kind: CapabilityClass) -> LocalizedStringKey {
        switch kind {
        case .read: return LocalizedStringKey("Read your data")
        case .write: return LocalizedStringKey("Change your data")
        case .ai: return LocalizedStringKey("Use your AI quota")
        case .local: return LocalizedStringKey("Save its own data")
        }
    }
}
