import SwiftUI

/// Lists models from a `ModelCatalogue` and lets the person pick one,
/// writing the choice into `selection`. Shared by the "Choose a Model" (text
/// generation) and "Choose a Pronunciation Model" (TTS) screens in
/// Settings — they differ only in which catalogue and which stored
/// selection they point at.
struct ModelPickerView: View {
    let title: LocalizedStringKey
    let catalogue: ModelCatalogue
    @Binding var selection: String?
    /// Shows Test buttons. Only for text models: pronunciation models can't answer a text question.
    var canTest = false
    /// When set, the list starts with a row that clears the selection (for example "Automatic").
    var automaticTitle: LocalizedStringKey?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var onlyWorking = false
    @State private var testingIDs: Set<String> = []
    @State private var testAllTask: Task<Void, Never>?
    @State private var testError: AIError?

    /// The models to list. "Working" keeps the ones that answered recently, and always the current choice.
    private var visibleModels: [AIModel] {
        guard onlyWorking else { return catalogue.models }
        return catalogue.models.filter { environment.modelStatus($0.id) == .working || $0.id == selection }
    }

    private var hasWorkingModels: Bool {
        catalogue.models.contains { environment.modelStatus($0.id) == .working }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                if catalogue.models.isEmpty {
                    emptyOrLoadingContent
                } else {
                    if let automaticTitle {
                        Button {
                            selection = nil
                            dismiss()
                        } label: {
                            HStack {
                                Text(automaticTitle).foregroundStyle(Theme.ink)
                                Spacer()
                                if selection == nil { Image(systemName: "checkmark").foregroundStyle(Theme.accentDeep) }
                            }
                        }
                        .accessibilityIdentifier("automaticModelRow")
                    }
                    ForEach(visibleModels) { model in
                        row(model)
                    }
                    if let selected = selection, !catalogue.models.contains(where: { $0.id == selected }) {
                        Label("Your selected model is no longer available.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                }
                if let testError {
                    Label(LocalizedStringKey(testError.userMessage), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
                } footer: {
                    if !catalogue.models.isEmpty {
                        Text("Marks come from your recent requests and tests. A model with no mark hasn't been used lately.")
                    }
                }
                .themedSection()
            }
            .glassScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if canTest, !catalogue.models.isEmpty {
                    ToolbarItem(placement: .primaryAction) { testAllButton }
                }
                if hasWorkingModels {
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(isOn: $onlyWorking) {
                            Label("Only Working Models", systemImage: "checkmark.seal")
                        }
                        .accessibilityIdentifier("onlyWorkingToggle")
                    }
                }
            }
            .onDisappear { testAllTask?.cancel() }
        }
    }

    private func row(_ model: AIModel) -> some View {
        Button {
            selection = model.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).foregroundStyle(Theme.ink)
                    if let description = model.description {
                        Text(description).font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                    }
                    if testingIDs.contains(model.id) {
                        HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Testing\u{2026}") }
                            .font(.caption).foregroundStyle(Theme.inkSecondary)
                    } else {
                        Self.badge(environment.modelStatus(model.id))
                    }
                }
                Spacer()
                if model.id == selection {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accentDeep)
                }
            }
        }
        .contextMenu {
            if canTest {
                Button("Test This Model", systemImage: "waveform.path.ecg") { Task { await test(model) } }
            }
        }
        .swipeActions(edge: .trailing) {
            if canTest {
                Button("Test") { Task { await test(model) } }.tint(Theme.accentDeep)
            }
        }
    }

    /// Icon and words, never colour alone.
    @ViewBuilder
    static func badge(_ status: ModelStatus) -> some View {
        switch status {
        case .unknown:
            EmptyView()
        case .working:
            Label("Working", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
        case .rateLimited:
            Label("Busy right now", systemImage: "hourglass").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
        case .quotaUsed:
            Label("Quota used up", systemImage: "gauge.with.dots.needle.100percent").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
        case .unstable:
            Label("Unstable", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
        case .unavailable:
            Label("Not available", systemImage: "xmark.octagon.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
        }
    }

    private var testAllButton: some View {
        Button {
            if testAllTask != nil {
                testAllTask?.cancel()
            } else {
                testAllTask = Task { await testAll(); testAllTask = nil }
            }
        } label: {
            if testAllTask != nil {
                Label("Stop Testing", systemImage: "stop.circle")
            } else {
                Label("Test All Models", systemImage: "waveform.path.ecg")
            }
        }
        .accessibilityIdentifier("testAllModelsButton")
    }

    private func test(_ model: AIModel) async {
        testError = nil
        testingIDs.insert(model.id)
        defer { testingIDs.remove(model.id) }
        if case .failure(let error) = await environment.testModel(model), ModelProbe.shouldStop(after: error) {
            testError = error
        }
    }

    /// One after another, so a key's rate limit isn't hit by a burst. Stops when the trouble isn't the model's.
    private func testAll() async {
        testError = nil
        for model in catalogue.models {
            if Task.isCancelled { return }
            testingIDs.insert(model.id)
            let result = await environment.testModel(model)
            testingIDs.remove(model.id)
            if case .failure(let error) = result, ModelProbe.shouldStop(after: error) {
                testError = error
                return
            }
        }
    }

    @ViewBuilder
    private var emptyOrLoadingContent: some View {
        switch catalogue.status {
        case .loading:
            ProgressView("Loading models…")
        case .failed(let error, _):
            ErrorBanner(message: LocalizedStringKey(error.userMessage), retryTitle: "Retry", onRetry: { Task { await refresh() } })
        default:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("No models yet.")
                Button("Fetch Models") { Task { await refresh() } }
            }
        }
    }

    private func refresh() async {
        guard let apiKey = environment.apiKey else { return }
        await catalogue.refresh(apiKey: apiKey, using: environment.ai)
    }
}
