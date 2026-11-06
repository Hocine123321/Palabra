import SwiftUI

/// Settings → Artifacts → Capabilities: what the AI is handed to build with, and what each kind of artifact can actually use.
/// Both kinds are listed, collapsed, and expand to show each capability.
struct ArtifactCapabilitiesView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section {
                Text("These are the only ways an artifact can reach your data. The AI is told about them when it builds one, and the app checks every call against what you allowed.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .themedSection()
            group(.app, title: "Interactive apps", icon: "app.dashed", note: "Can use everything below. You are asked once, before an app can use anything except its own storage.")
            group(.spec, title: "Pages", icon: "doc.text", note: "Only show your data in tables and charts, so they can read it and nothing more. They never ask.")
        }
        .glassScreen()
        .navigationTitle("Capabilities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ kind: ArtifactKind, title: LocalizedStringKey, icon: String, note: LocalizedStringKey) -> some View {
        let entries = CapabilityCatalog.entries(for: kind, registry: environment.capabilities)
        return Section {
            DisclosureGroup {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(entries, id: \.name) { entry in
                    row(entry)
                }
            } label: {
                Label {
                    HStack {
                        Text(title)
                        Spacer()
                        Text(verbatim: "\(entries.count)")
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
            }
            .tint(Theme.accentDeep)
            .accessibilityIdentifier("capabilityGroup.\(kind.rawValue)")
        }
        .themedSection()
    }

    private func row(_ entry: CapabilityCatalog.Entry) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                Text(verbatim: entry.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                if !entry.arguments.isEmpty {
                    Text("Takes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(entry.arguments, id: \.name) { argument in
                        Text(verbatim: "\(argument.name): \(argument.detail)")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Text("Gives back")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(verbatim: entry.returns)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.xs)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(Theme.ink)
                Text(Self.label(entry))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .tint(Theme.accentDeep)
        .accessibilityIdentifier("capability.\(entry.name)")
    }

    /// "Reads your data · asks first".
    static func label(_ entry: CapabilityCatalog.Entry) -> LocalizedStringKey {
        switch (entry.kind, entry.access) {
        case (.read, .automatic): return "Reads your data · never asks"
        case (.read, _): return "Reads your data · asks first"
        case (.write, _): return "Changes your data · asks first"
        case (.ai, _): return "Uses your AI quota · asks first"
        case (.local, _): return "Its own storage · never asks"
        }
    }
}
