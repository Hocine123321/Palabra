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
            generating(model)
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

    private func generating(_ model: ArtifactDraftModel) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView().controlSize(.large)
            Text("Generating…")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.ink)
            let asked = model.request.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .create, !asked.isEmpty {
                Text(verbatim: asked)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .glassCard()
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Request

    private func inputForm(_ model: ArtifactDraftModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                editor($model.request)
                if mode == .create {
                    formatSection($model.format)
                    ideasSection(model)
                } else {
                    quickChanges { model.request = ArtifactQuickChange.request(for: $0) }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    Task { await model.generate() }
                } label: {
                    Text("Generate")
                }
                .buttonStyle(.primary)
                .disabled(!model.canGenerate)
                .accessibilityIdentifier("generateArtifactButton")
                .padding(Theme.Spacing.md)
            }
            .background(Theme.background)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: mode == .create ? "sparkles" : "wand.and.stars")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if mode == .create {
                    Text("What do you want to make?").font(Theme.Font.title).foregroundStyle(Theme.ink)
                    Text("Describe it, or start from an idea.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("Describe the change").font(Theme.Font.title).foregroundStyle(Theme.ink)
                    Text("Everything you don't mention stays as it is.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func editor(_ text: Binding<String>) -> some View {
        let clipped = Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(ArtifactDraftModel.maxInput)) })
        return ZStack(alignment: .topLeading) {
            TextEditor(text: clipped)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(Theme.Spacing.sm)
                .accessibilityIdentifier("artifactRequestField")
            if text.wrappedValue.isEmpty {
                Text(mode == .create ? LocalizedStringKey("A table, a chart, a plan, a little game…") : LocalizedStringKey("For example: add a column for examples"))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                    .padding(.horizontal, Theme.Spacing.sm + 5)
                    .padding(.vertical, Theme.Spacing.sm + 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .glassCard()
        .overlay(alignment: .bottomTrailing) {
            if text.wrappedValue.count > ArtifactDraftModel.maxInput * 3 / 4 {
                Text(verbatim: "\(text.wrappedValue.count) / \(ArtifactDraftModel.maxInput)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    private func formatSection(_ format: Binding<ArtifactFormat>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Format").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Picker("Format", selection: format) {
                Text("Auto").tag(ArtifactFormat.auto)
                Text("Page").tag(ArtifactFormat.page)
                Text("Interactive app").tag(ArtifactFormat.app)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("artifactFormatPicker")
            Group {
                switch format.wrappedValue {
                case .auto: Text("The AI picks what fits your request.")
                case .page: Text("Tables, charts, roadmaps and checklists. Safe: it can only read your data.")
                case .app: Text("Buttons, games and trackers. It asks your permission before using your data.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func ideasSection(_ model: ArtifactDraftModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Ideas").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible(), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                ForEach(ArtifactIdea.all) { idea in
                    let selected = model.request == idea.prompt
                    Button {
                        Motion.animate(Motion.quick) {
                            model.request = idea.prompt
                            model.format = idea.format
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Image(systemName: idea.symbol).font(.title3).foregroundStyle(Theme.accent)
                            Text(LocalizedStringKey(idea.title)).font(Theme.Font.tile).foregroundStyle(Theme.ink)
                            Text(LocalizedStringKey(idea.subtitle)).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(Theme.Spacing.md)
                        .glassCard()
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .stroke(Theme.accent, lineWidth: selected ? 2 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("artifactIdea.\(idea.id)")
                }
            }
        }
    }

    /// Chips that put a ready-made change request into a field. `compact` = one scrolling row, no title (under a draft).
    private func quickChanges(compact: Bool = false, _ pick: @escaping (String) -> Void) -> some View {
        let chips = ForEach(ArtifactQuickChange.all, id: \.self) { key in
            Button { pick(key) } label: {
                Text(LocalizedStringKey(key))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.inkSecondary.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) { chips }
                }
            } else {
                Text("Quick changes").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                FlowLayout { chips }
            }
        }
    }

    private func preview(_ model: ArtifactDraftModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let draft = model.draft {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: draft.title)
                                .font(Theme.Font.heading)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: Theme.Spacing.sm)
                            Text(draft.kind == .app ? LocalizedStringKey("Interactive app") : LocalizedStringKey("Page"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
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
                quickChanges(compact: true) { refineText = ArtifactQuickChange.request(for: $0) }
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
