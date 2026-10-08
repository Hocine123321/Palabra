import SwiftUI

/// The create / update sheet: request -> generating -> live preview with Save, Refine, Discard.
struct ArtifactDraftView: View {
    let mode: ArtifactDraftModel.Mode
    /// Pre-filled request (for example the "Fix with AI" text).
    var initialRequest: String = ""
    var onSaved: (UUID) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: ArtifactDraftModel?
    @State private var refineText = ""
    @State private var previewState = InMemorySpecStateStore()
    /// One session and one log per open sheet, so `ai.generate` limits and errors survive re-renders.
    @State private var previewSession = ArtifactSession(artifactID: nil, dryRun: true)
    @State private var previewLog = ArtifactErrorLog()

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { Color.clear }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(mode == .create ? LocalizedStringKey("New Artifact") : LocalizedStringKey("Update"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            if model == nil {
                let created = ArtifactDraftModel(environment: environment, mode: mode)
                created.request = initialRequest
                model = created
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ArtifactDraftModel) -> some View {
        switch model.phase {
        case .input:
            inputForm(model)
        case .generating:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Generating…").foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            VStack(spacing: Theme.Spacing.md) {
                ErrorBanner(
                    message: LocalizedStringKey(error.userMessage),
                    onRetry: { Task { await model.retry() } },
                    secondaryTitle: "Dismiss",
                    onSecondary: { model.dismissFailure() }
                )
                Spacer()
            }
            .padding(Theme.Spacing.md)
        case .preview:
            preview(model)
        }
    }

    private func inputForm(_ model: ArtifactDraftModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(mode == .create ? LocalizedStringKey("Describe what you want") : LocalizedStringKey("Describe the change"))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            TextEditor(text: $model.request)
                .frame(minHeight: 160)
                .padding(Theme.Spacing.sm)
                .glassCard()
                .accessibilityIdentifier("artifactRequestField")
            Button {
                Task { await model.generate() }
            } label: {
                Text("Generate")
            }
            .buttonStyle(.primary)
            .disabled(!model.canGenerate)
            .accessibilityIdentifier("generateArtifactButton")
            Spacer()
        }
        .padding(Theme.Spacing.md)
    }

    private func preview(_ model: ArtifactDraftModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let draft = model.draft {
                        Text(verbatim: draft.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        previewBody(model, draft)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            Divider()
            VStack(spacing: Theme.Spacing.sm) {
                if let error = model.saveError {
                    Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(Theme.error)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Ask for a change", text: $refineText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("refineArtifactField")
                    Button("Refine") {
                        let change = refineText
                        refineText = ""
                        Task { await model.refine(change: change) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(refineText.trimmingCharacters(in: .whitespacesAndNewlines).count < ArtifactGeneratorLimits.minRequestLength)
                    .accessibilityIdentifier("refineArtifactButton")
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Discard", role: .destructive) {
                        model.discard()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("discardArtifactButton")
                    Button("Save") {
                        if let id = model.save() {
                            onSaved(id)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("saveArtifactButton")
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    /// Dry run: nothing the artifact does here can change app data.
    @ViewBuilder
    private func previewBody(_ model: ArtifactDraftModel, _ draft: ArtifactDraft) -> some View {
        switch draft.kind {
        case .spec:
            if let spec = try? JSONDecoder().decode(ArtifactSpec.self, from: draft.payload) {
                SpecRendererView(
                    spec: spec,
                    registry: environment.capabilities,
                    session: previewSession,
                    granted: SpecRendererView.grant(requests: draft.requests, registry: environment.capabilities),
                    state: previewState
                )
            }
        case .app:
            if model.needsDecision {
                ArtifactApprovalCard(capabilities: model.pending, onAllow: { model.allowPending() }, onDeny: { model.denyPending() })
            } else {
                AppRendererView(
                    html: String(decoding: draft.payload, as: UTF8.self),
                    registry: environment.capabilities,
                    session: previewSession,
                    granted: model.effectiveGrant,
                    log: previewLog,
                    colorScheme: colorScheme,
                    language: environment.appLanguage
                )
                .id("\(draft.payload.hashValue)-\(model.effectiveGrant.sorted())")
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }
        }
    }
}
