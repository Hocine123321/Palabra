import SwiftUI

/// One saved artifact: its current version rendered live, plus Update / Versions / Delete.
struct ArtifactDetailView: View {
    let artifactID: UUID

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot: Snapshot?
    @State private var showUpdate = false
    @State private var showVersions = false
    @State private var confirmDelete = false
    /// One session and log per open screen (the `ai.generate` budget and the error list live here).
    @State private var session: ArtifactSession
    @State private var log = ArtifactErrorLog()
    @State private var notNow = false
    @State private var webID = UUID()
    @State private var updateRequest = ""

    init(artifactID: UUID) {
        self.artifactID = artifactID
        _session = State(initialValue: ArtifactSession(artifactID: artifactID, dryRun: false))
    }

    private struct Snapshot {
        let title: String
        let kind: ArtifactKind
        let spec: ArtifactSpec?
        let html: String
        let requests: [String]
        let granted: Set<String>
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
                    Button("Update", systemImage: "wand.and.stars") {
                        updateRequest = ""
                        showUpdate = true
                    }
                    Button("Versions", systemImage: "clock.arrow.circlepath") { showVersions = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("artifactMenu")
            }
        }
        .sheet(isPresented: $showUpdate, onDismiss: reload) {
            ArtifactDraftView(mode: .update(artifactID: artifactID), initialRequest: updateRequest)
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
        switch snapshot.kind {
        case .spec:
            if let spec = snapshot.spec {
                ScrollView {
                    SpecRendererView(
                        spec: spec,
                        registry: environment.capabilities,
                        session: session,
                        granted: SpecRendererView.grant(requests: snapshot.requests, registry: environment.capabilities),
                        state: ArtifactSpecStateStore(artifactID: artifactID, repository: environment.artifacts)
                    )
                    .padding(Theme.Spacing.md)
                }
            } else {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load data", message: "Try updating this artifact.")
            }
        case .app:
            appContent(snapshot)
        }
    }

    @ViewBuilder
    private func appContent(_ snapshot: Snapshot) -> some View {
        let pending = ArtifactApproval.pending(kind: .app, requested: snapshot.requests, granted: snapshot.granted, registry: environment.capabilities)
        if !pending.isEmpty && !notNow {
            ScrollView {
                ArtifactApprovalCard(
                    capabilities: pending,
                    onAllow: {
                        environment.artifacts.setGranted(artifactID: artifactID, names: Array(snapshot.granted.union(pending.map(\.name))))
                        reload()
                    },
                    onDeny: { notNow = true }
                )
                .padding(Theme.Spacing.md)
            }
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                AppRendererView(
                    html: snapshot.html,
                    registry: environment.capabilities,
                    session: session,
                    granted: ArtifactApproval.effective(kind: .app, requested: snapshot.requests, granted: snapshot.granted, registry: environment.capabilities),
                    log: log,
                    colorScheme: colorScheme,
                    language: environment.appLanguage
                )
                .id(webID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !log.entries.isEmpty { errorsSection }
            }
        }
    }

    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Errors").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.error)
            ForEach(Array(log.entries.suffix(3).enumerated()), id: \.offset) { _, entry in
                Text(verbatim: entry).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(2)
            }
            Button("Fix with AI") {
                updateRequest = "Fix these runtime errors:\n" + log.summary
                showUpdate = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("fixWithAIButton")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityIdentifier("artifactErrors")
    }

    private func reload() {
        guard let artifact = environment.artifacts.artifact(id: artifactID) else {
            snapshot = nil
            return
        }
        let version = environment.artifacts.versions(artifactID: artifactID).first { $0.number == artifact.currentVersion }
        let payload = version?.payload ?? Data()
        snapshot = Snapshot(
            title: artifact.title,
            kind: artifact.kind,
            spec: artifact.kind == .spec ? try? JSONDecoder().decode(ArtifactSpec.self, from: payload) : nil,
            html: artifact.kind == .app ? String(decoding: payload, as: UTF8.self) : "",
            requests: version?.requestedNames ?? [],
            granted: Set(artifact.grantedNames)
        )
        log.clear()
        webID = UUID()
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
