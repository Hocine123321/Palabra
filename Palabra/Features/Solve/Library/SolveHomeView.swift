import PhotosUI
import SwiftUI

/// Capture or type a problem, solve it, and find earlier answers.
struct SolveHomeView: View {
    @Binding var path: [SolveRoute]
    @Environment(AppEnvironment.self) private var environment
    @State private var model: SolveModel?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var recents: [RecentRow] = []

    private struct RecentRow: Identifiable {
        let id: UUID
        let query: String
        let answer: String
    }

    private static let symbols = ["^", "\u{221A}(", "\u{03C0}", "\u{00D7}", "\u{00F7}", "(", ")", "=", "\u{2264}", "\u{2265}", "x"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model { content(model) }
        }
        .navigationTitle("Solve")
        .onAppear {
            if model == nil { model = SolveModel(tool: environment.solve) }
            reloadRecents()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onPhoto: { data in
                    showCamera = false
                    Task { await model?.recognize(imageData: data) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model?.recognize(imageData: data)
                }
                photoItem = nil
            }
        }
    }

    private func content(_ model: SolveModel) -> some View {
        @Bindable var bindable = model
        let tool = environment.solve
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if !tool.hasKey { setupCard }
                captureRow(model)
                problemEditor($bindable.input)
                symbolRow(model)
                solveButton(model)
                if let message = model.photoMessage {
                    Label(LocalizedStringKey(message), systemImage: "camera.metering.unknown")
                        .font(.subheadline)
                        .foregroundStyle(Theme.error)
                }
                if let error = model.error { errorView(error, model) }
                if !recents.isEmpty { recentsSection }
                usageFooter(tool)
            }
            .padding(Theme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Pieces

    private var setupCard: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Set up Wolfram|Alpha", systemImage: "key.fill")
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text("Solving uses your own free Wolfram|Alpha App ID (2,000 calls a month). Sign in at the developer portal, create an App ID for the Full Results API, and paste it here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) { WolframKeyField() }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func captureRow(_ model: SolveModel) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    captureLabel("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("takePhotoButton")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                captureLabel("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("choosePhotoButton")
        }
        .disabled(model.phase != .idle)
        .overlay {
            if model.phase == .reading {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Reading your photo\u{2026}").font(.subheadline).foregroundStyle(Theme.ink)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.surface, in: Capsule())
            }
        }
    }

    private func captureLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .glassCard()
    }

    private func problemEditor(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Problem").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(Theme.Spacing.sm)
                    .font(.system(.title3, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("solveInputField")
                if text.wrappedValue.isEmpty {
                    Text("Type or scan a problem, for example x^2 - 4 = 0")
                        .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                        .padding(.horizontal, Theme.Spacing.sm + 5)
                        .padding(.vertical, Theme.Spacing.sm + 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .glassCard()
            Text("Check the text a photo gave you before you solve it.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func symbolRow(_ model: SolveModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(Self.symbols.enumerated()), id: \.offset) { _, symbol in
                    Button { model.input += symbol } label: {
                        Text(verbatim: symbol)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minWidth: 40, minHeight: 40)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func solveButton(_ model: SolveModel) -> some View {
        Button {
            Task { if let id = await model.solve() { path.append(.result(id)); reloadRecents() } }
        } label: {
            if model.phase == .solving {
                HStack(spacing: Theme.Spacing.sm) { ProgressView(); Text("Solving\u{2026}") }
            } else {
                Text("Solve")
            }
        }
        .buttonStyle(.primary)
        .disabled(!model.canSolve)
        .accessibilityIdentifier("solveButton")
    }

    private func errorView(_ error: SolveError, _ model: SolveModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ErrorBanner(
                message: LocalizedStringKey(error.userMessage),
                retryTitle: nil,
                secondaryTitle: "Dismiss",
                onSecondary: { model.dismissError() }
            )
            if case .noResult(let suggestions) = error, !suggestions.isEmpty {
                Text("Did you mean").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        model.input = suggestion
                        Task { if let id = await model.solve() { path.append(.result(id)); reloadRecents() } }
                    } label: {
                        Text(verbatim: suggestion)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .padding(Theme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("solveError")
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            ForEach(recents) { row in
                Button { path.append(.result(row.id)) } label: {
                    GlassSurface {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(verbatim: row.query)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            if !row.answer.isEmpty {
                                Text(verbatim: row.answer)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accent)
                                    .lineLimit(1)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recentSolve")
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        environment.solve.history.delete(id: row.id)
                        reloadRecents()
                    }
                }
            }
        }
    }

    private func usageFooter(_ tool: SolveTool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("About \(tool.callsThisMonth) of \(SolveUsage.freeMonthlyCalls) free solves used this month")
                .accessibilityIdentifier("usageLabel")
            Text("Answers are saved, so opening one again costs nothing.")
            Text("Powered by Wolfram|Alpha")
        }
        .font(.caption)
        .foregroundStyle(Theme.inkSecondary)
    }

    private func reloadRecents() {
        recents = environment.solve.history.entries(limit: 10).map {
            RecentRow(id: $0.id, query: $0.query, answer: $0.result?.answerText.replacingOccurrences(of: "\n", with: ", ") ?? "")
        }
    }
}
