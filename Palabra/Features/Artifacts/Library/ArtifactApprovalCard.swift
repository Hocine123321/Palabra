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
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(capabilities.enumerated()), id: \.offset) { _, capability in
                    HStack(alignment: .center, spacing: Theme.Spacing.md) {
                        IconTile(systemImage: Self.icon(capability.kind), tint: Self.tint(capability.kind), size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.label(capability.kind))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: capability.summary)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.md - 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .innerFill(cornerRadius: Theme.Radius.medium)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onAllow) {
                    Text("Allow")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("allowArtifactButton")
                Button(action: onDeny) {
                    Text("Not now")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                .buttonStyle(.glassAction)
                .accessibilityIdentifier("denyArtifactButton")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private static func icon(_ kind: CapabilityClass) -> String {
        switch kind {
        case .read: return "eye"
        case .write: return "pencil"
        case .ai: return "sparkles"
        case .local: return "internaldrive"
        }
    }

    private static func tint(_ kind: CapabilityClass) -> Color {
        switch kind {
        case .read: return Theme.tileTints[2]
        case .write: return Theme.tileTints[4]
        case .ai: return Theme.tileTints[0]
        case .local: return Theme.tileTints[1]
        }
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
