import SwiftUI
import UniformTypeIdentifiers

/// The result of a library import or export, kept structured (rather than a pre-formatted String) so the
/// count-bearing cases can still be displayed with real, localizable `Text` interpolation.
private enum DataMessage {
    case imported(LibraryBackupService.ImportSummary)
    case importFailed(LibraryBackupService.Failure)
    case unreadable
    /// The export file could not be made.
    case exportFailed
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
    @State private var exported: LibraryBackupService.ExportSummary?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showImporter = false
    @State private var dataMessage: DataMessage?

    var body: some View {
        Form {
            Section("AI") {
                keyRow
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "cpu", tint: Theme.tileTints[0], size: 30)
                        Text("Model")
                        Spacer()
                        ModelValueLabel(id: environment.selectedModel?.id, placeholder: "Not selected")
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
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "lifepreserver", tint: Theme.tileTints[4], size: 30)
                        Text("Reliability")
                        Spacer()
                        Text(environment.hasFallbackKey ? LocalizedStringKey("Backup key on") : LocalizedStringKey("No backup key"))
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
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "waveform", tint: Theme.tileTints[2], size: 30)
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
                NavigationLink {
                    OrganizationSettingsView()
                } label: {
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "square.grid.2x2", tint: Theme.tileTints[1], size: 30)
                        Text("Organization")
                    }
                }
            }
            .themedSection()

            Section("Solve") {
                NavigationLink {
                    SolveSettingsView()
                } label: {
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "function", tint: Theme.tileTints[3], size: 30)
                        Text("Solve Settings")
                    }
                }
                .accessibilityIdentifier("solveSettingsLink")
            }
            .themedSection()

            Section("Assistant") {
                NavigationLink {
                    AssistantSettingsView()
                } label: {
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: "bubble.left.and.bubble.right", tint: Theme.tileTints[2], size: 30)
                        Text("Chat Assistant")
                    }
                }
            }
            .themedSection()

            Section("Study") {
                Stepper(value: newCardsBinding, in: 0...100, step: 5) {
                    Text("New cards per day: \(environment.newCardsPerDay)")
                }
            }
            .themedSection()

            Section("Data") {
                if let exported {
                    ShareLink(item: exported.url) {
                        Label("Share Library File", systemImage: "square.and.arrow.up")
                    }
                    Text("Exported \(exported.words) words, \(exported.clips) pronunciations, \(exported.cards) cards, \(exported.chats) chats (\(ByteCountFormatter.string(fromByteCount: exported.bytes, countStyle: .file))).")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Button {
                    Task { await runExport() }
                } label: {
                    Label("Export Library", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(isExporting || isImporting)
                Button { showImporter = true } label: {
                    Label("Import Library", systemImage: "square.and.arrow.down")
                }
                .disabled(isExporting || isImporting)
                if isExporting || isImporting {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Group {
                            if isExporting { Text("Exporting…") } else { Text("Importing…") }
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                }
                if let dataMessage {
                    dataMessageText(dataMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Button("Delete All Words", role: .destructive) { showDeleteAllConfirm = true }
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Settings")
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(
                title: "Choose a Model",
                catalogue: environment.catalogue,
                selection: Binding(get: { environment.selectedModelID }, set: { environment.selectedModelID = $0 }),
                canTest: true
            )
        }
        .sheet(isPresented: $showTTSModelPicker) {
            ModelPickerView(
                title: "Choose a Pronunciation Model",
                catalogue: environment.ttsCatalogue,
                selection: Binding(get: { environment.selectedTTSModelID }, set: { environment.selectedTTSModelID = $0 })
            )
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .json], onCompletion: handleImport)
        .confirmationDialog("Remove your API key?", isPresented: $showRemoveKeyConfirm) {
            Button("Remove", role: .destructive) { environment.removeAPIKey() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete all \(environment.repository.wordCount()) words? This can't be undone.",
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

    private func runExport() async {
        isExporting = true
        dataMessage = nil
        defer { isExporting = false }
        do {
            exported = try await environment.makeBackupService().export()
        } catch {
            exported = nil
            dataMessage = .exportFailed
        }
    }

    @ViewBuilder
    private func dataMessageText(_ message: DataMessage) -> some View {
        switch message {
        case .imported(let summary):
            VStack(alignment: .leading, spacing: 2) {
                Text("Imported \(summary.words.imported), skipped \(summary.words.skipped).")
                if summary.words.updated > 0 {
                    Text("Updated \(summary.words.updated) words already in your library.")
                }
                if summary.decks + summary.cards + summary.progress + summary.reviews > 0 {
                    Text("Study: \(summary.decks) decks, \(summary.cards) cards, \(summary.progress) with progress, \(summary.reviews) reviews restored.")
                }
                if summary.chats > 0 {
                    Text("Chats added: \(summary.chats).")
                }
                if summary.exams > 0 {
                    Text("Exams added: \(summary.exams).")
                }
                if summary.words.clipsRestored > 0 {
                    Text("Pronunciations restored: \(summary.words.clipsRestored).")
                }
                if summary.clipsLost > 0 {
                    Text("\(summary.clipsLost) pronunciations couldn't be read from the file.")
                }
                if summary.words.invalid > 0 {
                    Text("\(summary.words.invalid) entries had no word and were ignored.")
                }
            }
        case .importFailed(let failure):
            switch failure {
            case .notALibrary: Text("That file isn't a Palabra export.")
            case .unsupportedVersion: Text("That file was made by a newer version of Palabra.")
            case .incomplete: Text("That file is incomplete. Copy or download it again.")
            case .corrupt: Text("That file is damaged and can't be imported.")
            case .saveFailed: Text("Some of the library couldn't be saved. Import the same file again: what was added is skipped.")
            case .writeFailed: Text("Couldn't create the export file.")
            }
        case .unreadable:
            Text("Couldn't read that file.")
        case .exportFailed:
            Text("Couldn't create the export file.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            dataMessage = .unreadable
            return
        }
        isImporting = true
        dataMessage = nil
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            do {
                dataMessage = .imported(try await environment.makeBackupService().importLibrary(from: url))
            } catch let failure as LibraryBackupService.Failure {
                dataMessage = .importFailed(failure)
            } catch {
                dataMessage = .unreadable
            }
        }
    }
}
