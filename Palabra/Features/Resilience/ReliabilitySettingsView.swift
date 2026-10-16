import SwiftUI

/// Everything about keeping the AI working: the backup API key, how the app retries, and a
/// log of recent problems so nothing fails silently.
struct ReliabilitySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var keyInput = ""
    @State private var isVerifying = false
    @State private var keyError: String?
    @State private var showRemoveConfirm = false
    @State private var showBackupModelPicker = false

    var body: some View {
        @Bindable var env = environment
        Form {
            fallbackSection
            backupModelSection
            Section {
                Toggle("Retry Automatically", isOn: $env.retryPolicy.autoRetryEnabled)
                if environment.retryPolicy.autoRetryEnabled {
                    Stepper("Automatic Tries: \(environment.retryPolicy.maxAutomaticAttempts)", value: $env.retryPolicy.maxAutomaticAttempts, in: 1...6)
                    Stepper("First Wait: \(Int(environment.retryPolicy.baseDelay)) s", value: $env.retryPolicy.baseDelay, in: 1...20, step: 1)
                    Stepper("Longest Automatic Wait: \(Int(environment.retryPolicy.maxAutomaticWait)) s", value: $env.retryPolicy.maxAutomaticWait, in: 5...120, step: 5)
                }
            } header: {
                Text("Retrying")
            } footer: {
                Text("When a request fails, the app waits and tries again, doubling the wait each time. If it still fails, it asks whether to stop or retry with much longer waits. Turn this off to be asked immediately.")
            }
            .themedSection()
            recentProblemsSection
        }
        .glassScreen()
        .navigationTitle("Reliability")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBackupModelPicker) {
            ModelPickerView(
                title: "Choose a Backup Model",
                catalogue: environment.catalogue,
                selection: $env.retryPolicy.backupModelID,
                canTest: true,
                automaticTitle: "Automatic"
            )
        }
        .confirmationDialog("Remove the backup key?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) { environment.removeFallbackKey() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: backup model

    @ViewBuilder
    private var backupModelSection: some View {
        @Bindable var env = environment
        Section {
            Toggle("Switch Models Automatically", isOn: $env.retryPolicy.switchModelEnabled)
                .accessibilityIdentifier("switchModelsToggle")
            if environment.retryPolicy.switchModelEnabled {
                Button {
                    showBackupModelPicker = true
                } label: {
                    HStack {
                        Text("Backup Model").foregroundStyle(Theme.ink)
                        Spacer()
                        ModelValueLabel(id: environment.retryPolicy.backupModelID, placeholder: "Automatic")
                    }
                }
                .accessibilityIdentifier("backupModelRow")
            }
        } header: {
            Text("Backup Model")
        } footer: {
            Text("When your model is busy, out of quota or removed, the app answers with another one that works and tells you. Automatic picks from the models marked Working first.")
        }
        .themedSection()
    }

    // MARK: backup key

    @ViewBuilder
    private var fallbackSection: some View {
        Section {
            if environment.hasFallbackKey, let key = environment.fallbackAPIKey {
                HStack {
                    Label("Backup key", systemImage: "key.horizontal")
                    Spacer()
                    Text(KeychainStore.mask(key)).foregroundStyle(Theme.inkSecondary).monospaced()
                }
                keyStatusRow
                Button("Remove Backup Key", role: .destructive) { showRemoveConfirm = true }
            } else {
                SecureField("Paste a key from another account", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("fallbackKeyField")
                if let keyError {
                    Text(LocalizedStringKey(keyError)).font(.footnote).foregroundStyle(Theme.error)
                }
                Button {
                    Task { await saveFallback() }
                } label: {
                    HStack { Text("Verify and Save"); if isVerifying { Spacer(); ProgressView() } }
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                .accessibilityIdentifier("saveFallbackKeyButton")
            }
        } header: {
            Text("Backup API Key")
        } footer: {
            Text("Used automatically when your main key keeps failing, for example when it runs out of quota. Use a key from a different Google account, since keys from the same account share one quota.")
        }
        .themedSection()
    }

    @ViewBuilder
    private var keyStatusRow: some View {
        let center = environment.resilience
        HStack {
            Text("Using now")
            Spacer()
            Text(center.activeSlot == .primary ? LocalizedStringKey("Main key") : LocalizedStringKey("Backup key"))
                .foregroundStyle(center.activeSlot == .primary ? Theme.inkSecondary : Theme.accentDeep)
        }
        if center.health.isBenched(.primary, now: Date()), let reason = center.health.reason(.primary) {
            Text(LocalizedStringKey(Self.benchText(reason)))
                .font(.footnote).foregroundStyle(Theme.error)
        }
    }

    /// A log line's subject. Most are fixed phrases; "Generating "word"" carries the word.
    static func activityText(_ what: String) -> Text {
        let prefix = "Generating \""
        if what.hasPrefix(prefix), what.hasSuffix("\""), what.count > prefix.count {
            return Text("Generating \"\(String(what.dropFirst(prefix.count).dropLast()))\"")
        }
        return Text(LocalizedStringKey(what))
    }

    /// "<reason>. <what happened>" for a log line, each part translated on its own.
    static func detailText(_ entry: ResilienceCenter.LogEntry) -> Text {
        Text(LocalizedStringKey(entry.error.shortReason)) + Text(". ") + Text(LocalizedStringKey(entry.outcome))
    }

    static func benchText(_ reason: KeyHealth.Reason) -> String {
        switch reason {
        case .rateLimited: return "Main key is rate limited. It will be tried again in about a minute."
        case .quotaExhausted: return "Main key is out of quota. It will be tried again in about an hour."
        case .rejected: return "Main key was rejected by Google. Check it in Settings."
        case .flaky: return "Main key kept failing. It will be tried again shortly."
        }
    }

    private func saveFallback() async {
        keyError = nil
        isVerifying = true
        defer { isVerifying = false }
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == environment.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) {
            keyError = "That's the same as your main key. Use a key from a different account."
            return
        }
        // Verify against the plain client: a bad key must fail fast, not trigger retries.
        switch await environment.rawAI.listModels(apiKey: trimmed) {
        case .success:
            commitFallback(trimmed)
        case .failure(let error):
            switch error {
            case .invalidAPIKey, .permissionDenied:
                keyError = error.userMessage
            case .offline:
                keyError = error.userMessage
            default:
                // A temporary failure while checking (timeout, server error, rate limit) says
                // nothing bad about the key itself, so keep it.
                commitFallback(trimmed)
            }
        }
    }

    private func commitFallback(_ key: String) {
        if environment.saveFallbackKey(key) { keyInput = "" } else { keyError = "Couldn't save that key." }
    }

    // MARK: log

    @ViewBuilder
    private var recentProblemsSection: some View {
        let log = environment.resilience.log
        Section {
            if log.isEmpty {
                Text("No problems so far.").foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Self.activityText(entry.what).font(.subheadline).foregroundStyle(Theme.ink)
                        Self.detailText(entry).font(.footnote).foregroundStyle(Theme.inkSecondary)
                        Text(entry.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.inkSecondary)
                    }
                }
                Button("Clear", role: .destructive) { environment.resilience.clearLog() }
            }
        } header: {
            Text("Recent Problems")
        }
        .themedSection()
    }
}
