import SwiftUI

/// One saved artifact: its current version rendered live, plus Update / Versions / Delete.
struct ArtifactDetailView: View {
    let artifactID: UUID

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: Snapshot?
    @State private var showUpdate = false
    @State private var showVersions = false
    @State private var confirmDelete = false

    private struct Snapshot {
        let title: String
        let kind: ArtifactKind
        let spec: ArtifactSpec?
        let requests: [String]
    }

    var body: some View {
        Group {
            if let snapshot { content(snapshot) } else { ProgressView() }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: snapshot?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Update", systemImage: "wand.and.stars") { showUpdate = true }
                    Button("Versions", systemImage: "clock.arrow.circlepath") { showVersions = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("artifactMenu")
            }
        }
        .sheet(isPresented: $showUpdate, onDismiss: reload) {
            ArtifactDraftView(mode: .update(artifactID: artifactID))
        }
        .sheet(isPresented: $showVersions, onDismiss: reload) {
            ArtifactVersionsView(artifactID: artifactID)
        }
        .confirmationDialog("Delete this artifact?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                environment.artifacts.delete(id: artifactID)
                dismiss()
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot) -> some View {
        if snapshot.kind == .app {
            EmptyStateView(systemImage: "app.dashed", title: "Not supported in this version yet", message: "Update Palabra to open this artifact.")
        } else if let spec = snapshot.spec {
            ScrollView {
                SpecRendererView(
                    spec: spec,
                    registry: environment.capabilities,
                    session: ArtifactSession(artifactID: artifactID, dryRun: false),
                    granted: SpecRendererView.grant(requests: snapshot.requests, registry: environment.capabilities),
                    state: ArtifactSpecStateStore(artifactID: artifactID, repository: environment.artifacts)
                )
                .padding(Theme.Spacing.md)
            }
        } else {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load data", message: "Try updating this artifact.")
        }
    }

    private func reload() {
        guard let artifact = environment.artifacts.artifact(id: artifactID) else {
            snapshot = nil
            return
        }
        let version = environment.artifacts.versions(artifactID: artifactID).first { $0.number == artifact.currentVersion }
        let spec = version.flatMap { try? JSONDecoder().decode(ArtifactSpec.self, from: $0.payload) }
        snapshot = Snapshot(title: artifact.title, kind: artifact.kind, spec: spec, requests: version?.requestedNames ?? [])
    }
}

/// Version history with a Restore button per older version. Restoring adds a new version
/// (history is never rewritten).
struct ArtifactVersionsView: View {
    let artifactID: UUID

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let current = environment.artifacts.artifact(id: artifactID)?.currentVersion ?? 0
                    ForEach(environment.artifacts.versions(artifactID: artifactID), id: \.number) { version in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Version \(version.number)").font(Theme.Font.rowTitle).foregroundStyle(Theme.ink)
                                Text(verbatim: version.prompt).font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                                Text(version.createdAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            if version.number == current {
                                Text("Current").font(.caption).foregroundStyle(Theme.accent)
                            } else {
                                Button("Restore") {
                                    _ = environment.artifacts.restore(artifactID: artifactID, versionNumber: version.number, now: Date())
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("restoreVersion-\(version.number)")
                            }
                        }
                    }
                }
                .themedSection()
            }
            .creamScreen()
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
