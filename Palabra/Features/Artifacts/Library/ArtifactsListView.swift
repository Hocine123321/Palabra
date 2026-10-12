import SwiftData
import SwiftUI

/// The Artifacts page: every saved artifact, newest first, and the entry to create one.
struct ArtifactsListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Artifact.updatedAt, order: .reverse) private var artifacts: [Artifact]
    @State private var showNew = false
    @State private var pendingDelete: UUID?

    var body: some View {
        Group {
            if artifacts.isEmpty {
                EmptyStateView(systemImage: "sparkles", title: "No artifacts yet", message: "Ask the AI for a table, chart, roadmap or checklist.")
                    .frame(maxHeight: .infinity)
                    .background(ScreenBackdrop())
            } else {
                List {
                    Section {
                        ForEach(artifacts) { artifact in
                            NavigationLink(value: Router.Destination.artifactDetail(artifact.id)) {
                                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                                    IconTile(
                                        systemImage: artifact.kind == .app ? "gamecontroller.fill" : "doc.text.fill",
                                        tint: Theme.tint(for: artifact.id.uuidString),
                                        size: 40
                                    )
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        Text(verbatim: artifact.title)
                                            .font(Theme.Font.rowTitle)
                                            .foregroundStyle(Theme.ink)
                                        Text(artifact.updatedAt, format: .dateTime.month().day().hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkSecondary)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                            .accessibilityIdentifier("artifactRow")
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDelete = artifact.id }
                            }
                        }
                    }
                    .themedSection()
                }
                .glassScreen()
            }
        }
        .navigationTitle("Artifacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Artifact")
                    .accessibilityIdentifier("newArtifactButton")
            }
        }
        .sheet(isPresented: $showNew) { ArtifactDraftView(mode: .create) }
        .confirmationDialog("Delete this artifact?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { environment.artifacts.delete(id: id) }
                pendingDelete = nil
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}
