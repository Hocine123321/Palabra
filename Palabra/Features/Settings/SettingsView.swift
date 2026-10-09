import SwiftUI
import UniformTypeIdentifiers

/// The result of a library import, kept structured (rather than a
/// pre-formatted String) so the count-bearing case can still be displayed
/// with a real, localizable `Text` interpolation.
private enum ImportResultMessage {
    case imported(count: Int, skipped: Int)
    case invalidFile
    case unreadable
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var keyInput = ""
    @State private var isEditingKey = false
    @State private var isVerifying = false
    @State private var keyError: String?
    @State private var showRemoveKeyConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var showModelPicker = false
    @State private var showTTSModelPicker = false
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResultMessage: ImportResultMessage?

    var body: some View {
        Form {
            Section("AI") {
                keyRow
                Button {
                    showModelPicker = true
                } label: {
                    HStack {
                        Text("Model")
                        Spacer()
                        if let name = environment.selectedModel?.displayName {
                            Text(name).foregroundStyle(Theme.inkSecondary)
                        } else {
                            Text("Not selected").foregroundStyle(Theme.inkSecondary)
                        }
                        if environment.selectedModelID != nil, environment.selectedModel == nil {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                        }
                    }
                }
                Button {
                    Task { await refreshModels() }
                } label: {
                    HStack {
                        Text("Refresh Models")
                        Spacer()
                        if case .loading = environment.catalogue.status { ProgressView() }
                    }
                }
                .disabled(!environment.hasAPIKey)
                catalogueStatusRow(environment.catalogue.status)
            }
            .themedSection()

            Section {
                NavigationLink {
                    ReliabilitySettingsView()
                } label: {
                    HStack {
                        Text("Reliability")
                        Spacer()
                        Text(environment.hasFallbackKey ? "Backup key on" : "No backup key")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            } footer: {
                Text("Automatic retries and a backup API key for when your main one fails.")
            }
            .themedSection()

            Section {
                Button {
                    showTTSModelPicker = true
                } label: {
                    HStack {
                        Text("Pronunciation Model")
                        Spacer()
                        if let name = environment.selectedTTSModel?.displayName {
                            Text(name).foregroundStyle(Theme.inkSecondary)
                        } else {
                            Text("Not selected").foregroundStyle(Theme.inkSecondary)
                        }
                        if environment.selectedTTSModelID != nil, environment.selectedTTSModel == nil {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                        }
                    }
                }
                Button {
                    Task { await refreshTTSModels() }
                } label: {
                    HStack {
                        Text("Refresh Models")
                        Spacer()
                        if case .loading = environment.ttsCatalogue.status { ProgressView() }
                    }
                }
                .disabled(!environment.hasAPIKey)
                catalogueStatusRow(environment.ttsCatalogue.status)
            } header: {
                Text("Pronunciation")
            } footer: {
                Text("Used to generate spoken audio for the words you save.")
            }
            .themedSection()

            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    Text("System").tag(SettingsStore.AppearanceMode.system)
                    Text("Light").tag(SettingsStore.AppearanceMode.light)
                    Text("Dark").tag(SettingsStore.AppearanceMode.dark)
                }
            }
            .themedSection()

            Section("Language") {
                Picker("App Language", selection: appLanguageBinding) {
                    Text("English").tag(SupportedLanguage.english)
                    Text("Arabic").tag(SupportedLanguage.arabic)
                }
                Picker("AI Language", selection: aiLanguageBinding) {
                    Text("English").tag(SupportedLanguage.english)
                    Text("Arabic").tag(SupportedLanguage.arabic)
                }
            }
            .themedSection()

            Section("Library") {
                Picker("Layout", selection: layoutBinding) {
                    Text("Grid").tag(SettingsStore.LibraryLayout.grid)
                    Text("Readability").tag(SettingsStore.LibraryLayout.list)
                }
                .pickerStyle(.segmented)
                NavigationLink("Organization") { OrganizationSettingsView() }
            }
            .themedSection()

            Section("Assistant") {
                NavigationLink("Chat Assistant") { AssistantSettingsView() }
            }
            .themedSection()

            Section("Study") {
                Stepper(value: newCardsBinding, in: 0...100, step: 5) {
                    Text("New cards per day: \(environment.newCardsPerDay)")
                }
            }
            .themedSection()

            Section("Data") {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export Library", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button { exportURL = writeExportFile() } label: {
                        Label("Export Library", systemImage: "square.and.arrow.up")
                    }
                }
                Button { showImporter = true } label: {
                    Label("Import Library", systemImage: "square.and.arrow.down")
                }
                if let importResultMessage {
                    importResultText(importResultMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Button("Delete All Words", role: .destructive) { showDeleteAllConfirm = true }
            }
            .themedSection()
        }
        .creamScreen()
        .navigationTitle("Settings")
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(
                title: "Choose a Model",
                catalogue: environment.catalogue,
                selection: Binding(get: { environment.selectedModelID }, set: { environment.selectedModelID = $0 })
            )
        }
        .sheet(isPresented: $showTTSModelPicker) {
            ModelPickerView(
                title: "Choose a Pronunciation Model",
                catalogue: environment.ttsCatalogue,
                selection: Binding(get: { environment.selectedTTSModelID }, set: { environment.selectedTTSModelID = $0 })
            )
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], onCompletion: handleImport)
        .confirmationDialog("Remove your API key?", isPresented: $showRemoveKeyConfirm) {
            Button("Remove", role: .destructive) { environment.removeAPIKey() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete all \(environment.repository.allWords().count) words? This can't be undone.",
            isPresented: $showDeleteAllConfirm
        ) {
            Button("Delete All", role: .destructive) { environment.repository.deleteAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        if environment.hasAPIKey, !isEditingKey {
            HStack {
                Text("API Key")
                Spacer()
                Text(KeychainStore.mask(environment.apiKey ?? ""))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Button("Replace Key") { isEditingKey = true; keyInput = "" }
            Button("Remove Key", role: .destructive) { showRemoveKeyConfirm = true }
        } else {
            SecureField("Google API Key", text: $keyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let keyError {
                Text(LocalizedStringKey(keyError)).font(.footnote).foregroundStyle(Theme.error)
            }
            Button {
                Task { await saveKey() }
            } label: {
                if isVerifying { ProgressView() } else { Text("Save Key") }
            }
            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
            if environment.hasAPIKey {
                Button("Cancel") { isEditingKey = false; keyError = nil }
            }
        }
    }

    private var appLanguageBinding: Binding<SupportedLanguage> {
        Binding(get: { environment.appLanguage }, set: { environment.appLanguage = $0 })
    }

    private var aiLanguageBinding: Binding<SupportedLanguage> {
        Binding(get: { environment.aiLanguage }, set: { environment.aiLanguage = $0 })
    }

    private var appearanceBinding: Binding<SettingsStore.AppearanceMode> {
        Binding(get: { environment.appearanceMode }, set: { environment.appearanceMode = $0 })
    }

    private var newCardsBinding: Binding<Int> {
        Binding(get: { environment.newCardsPerDay }, set: { environment.newCardsPerDay = $0 })
    }

    private var layoutBinding: Binding<SettingsStore.LibraryLayout> {
        Binding(get: { environment.libraryLayout }, set: { environment.libraryLayout = $0 })
    }

    @ViewBuilder
    private func catalogueStatusRow(_ status: ModelCatalogue.Status) -> some View {
        switch status {
        case .idle, .loading:
            EmptyView()
        case .loaded(let date):
            Text("Updated \(date.formatted(.relative(presentation: .named)))")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        case .failed(let error, let hasCache):
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(error.userMessage))
                if hasCache {
                    Text("Showing the last saved list.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.error)
        }
    }

    private func saveKey() async {
        keyError = nil
        isVerifying = true
        defer { isVerifying = false }
        switch await APIKeyEntry.verifyAndSave(keyInput, environment: environment) {
        case .invalid:
            keyError = AIError.invalidAPIKey.userMessage
        case .saved, .savedWithWarning:
            isEditingKey = false
            keyInput = ""
        }
    }

    private func refreshModels() async {
        guard let apiKey = environment.apiKey else { return }
        await environment.catalogue.refresh(apiKey: apiKey, using: environment.ai)
    }

    private func refreshTTSModels() async {
        guard let apiKey = environment.apiKey else { return }
        await environment.ttsCatalogue.refresh(apiKey: apiKey, using: environment.ai)
    }

    private func writeExportFile() -> URL? {
        let data = environment.repository.exportData()
        let name = "Palabra-Library-\(Date().formatted(.iso8601.year().month().day())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    @ViewBuilder
    private func importResultText(_ result: ImportResultMessage) -> some View {
        switch result {
        case .imported(let count, let skipped):
            Text("Imported \(count), skipped \(skipped).")
        case .invalidFile:
            Text("That file isn't a Palabra export.")
        case .unreadable:
            Text("Couldn't read that file.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importResultMessage = .unreadable
                return
            }
            do {
                let outcome = try environment.repository.importData(data)
                importResultMessage = .imported(count: outcome.imported, skipped: outcome.skipped)
            } catch {
                importResultMessage = .invalidFile
            }
        case .failure:
            importResultMessage = .unreadable
        }
    }
}
