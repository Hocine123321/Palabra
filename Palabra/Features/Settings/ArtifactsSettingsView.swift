import SwiftUI

/// Settings → Artifacts: how big an artifact the AI may write, and the defaults of the Artifacts feature.
struct ArtifactsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Maximum File Size")
                        Spacer()
                        Text(verbatim: "\(environment.artifactSettings.maxOutputKB) KB")
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Slider(
                        value: sizeBinding,
                        in: Double(ArtifactOutputBudget.minKB)...Double(ArtifactOutputBudget.maxKB),
                        step: Double(ArtifactOutputBudget.stepKB)
                    )
                    .accessibilityIdentifier("artifactMaxSizeSlider")
                    .accessibilityValue(Text(verbatim: "\(environment.artifactSettings.maxOutputKB) KB"))
                }
                if let reachable = modelReachableKB {
                    Label {
                        Text("Your model can write about \(reachable) KB at most, so bigger artifacts will be cut off.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                    }
                    .font(.footnote)
                }
                Button("Reset to Default") {
                    env.artifactSettings.maxOutputKB = ArtifactOutputBudget.defaultKB
                }
                .disabled(environment.artifactSettings.maxOutputKB == ArtifactOutputBudget.defaultKB)
            } header: {
                Text("In-App AI Output")
            } footer: {
                Text("The most the in-app AI may write for one artifact (8 to 128 KB, 20 KB by default). Bigger files take longer, use more of your quota and can be cut off if the model cannot write that much. Pages you bring from another AI can be up to 2 MB.")
            }
            .themedSection()

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Maximum File Size")
                        Spacer()
                        Text(verbatim: ArtifactPrompts.describeLimit(kb: environment.artifactSettings.externalMaxKB))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Slider(
                        value: externalSizeBinding,
                        in: Double(ArtifactOutputBudget.externalMinKB)...Double(ArtifactOutputBudget.externalMaxKB),
                        step: Double(ArtifactOutputBudget.externalStepKB)
                    )
                    .accessibilityIdentifier("artifactExternalMaxSizeSlider")
                    .accessibilityValue(Text(verbatim: ArtifactPrompts.describeLimit(kb: environment.artifactSettings.externalMaxKB)))
                }
                Button("Reset to Default") {
                    env.artifactSettings.externalMaxKB = ArtifactOutputBudget.externalDefaultKB
                }
                .disabled(environment.artifactSettings.externalMaxKB == ArtifactOutputBudget.externalDefaultKB)
            } header: {
                Text("External AI Output")
            } footer: {
                Text("The most a page from another AI app (Claude, ChatGPT) may be when you upload or paste it. The copied prompt tells that AI the same limit.")
            }
            .themedSection()

            Section {
                Picker("Default Format", selection: formatBinding) {
                    Text("Auto").tag(ArtifactSettings.DefaultFormat.auto)
                    Text("Page").tag(ArtifactSettings.DefaultFormat.page)
                    if environment.artifactSettings.allowAppArtifacts {
                        Text("Interactive app").tag(ArtifactSettings.DefaultFormat.app)
                    }
                }
                Toggle("Allow Interactive Apps", isOn: appsBinding)
            } header: {
                Text("Creating")
            } footer: {
                Text("Interactive apps run in a locked-down web view and ask permission before using your data. Turning them off only stops new ones; saved apps keep working.")
            }
            .themedSection()

            Section {
                NavigationLink {
                    ArtifactCapabilitiesView()
                } label: {
                    Label("Capabilities", systemImage: "puzzlepiece.extension")
                }
                .accessibilityIdentifier("artifactCapabilitiesLink")
            } footer: {
                Text("What the AI is handed to build with, and what pages and interactive apps can actually use.")
            }
            .themedSection()

            Section {
                LabeledContent("Saved Artifacts") { Text(verbatim: "\(artifactCount)").monospacedDigit() }
                LabeledContent("Space Used") { Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(storedBytes), countStyle: .file)).monospacedDigit() }
            } header: {
                Text("Library")
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Artifacts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(environment.artifactSettings.maxOutputKB) },
            set: { environment.artifactSettings.maxOutputKB = ArtifactOutputBudget.clampedKB(Int($0)) }
        )
    }

    private var externalSizeBinding: Binding<Double> {
        Binding(
            get: { Double(environment.artifactSettings.externalMaxKB) },
            set: { environment.artifactSettings.externalMaxKB = ArtifactOutputBudget.clampedExternalKB(Int($0)) }
        )
    }

    /// A saved `.app` while apps are off would have no matching row in the picker: show it as Auto.
    private var formatBinding: Binding<ArtifactSettings.DefaultFormat> {
        Binding(
            get: {
                let saved = environment.artifactSettings.defaultFormat
                return saved == .app && !environment.artifactSettings.allowAppArtifacts ? .auto : saved
            },
            set: { environment.artifactSettings.defaultFormat = $0 }
        )
    }

    private var appsBinding: Binding<Bool> {
        Binding(
            get: { environment.artifactSettings.allowAppArtifacts },
            set: {
                environment.artifactSettings.allowAppArtifacts = $0
                if !$0, environment.artifactSettings.defaultFormat == .app { environment.artifactSettings.defaultFormat = .auto }
            }
        )
    }

    /// Set only when the chosen model cannot write as much as the setting asks for.
    private var modelReachableKB: Int? {
        guard let limit = environment.selectedModel?.outputTokenLimit else { return nil }
        let reachable = ArtifactOutputBudget.reachableKB(tokenLimit: limit)
        return reachable < environment.artifactSettings.maxOutputKB ? reachable : nil
    }

    private var artifactCount: Int { environment.artifacts.artifacts().count }

    private var storedBytes: Int {
        environment.artifacts.artifacts().reduce(0) { total, artifact in
            total + environment.artifacts.versions(artifactID: artifact.id).reduce(0) { $0 + $1.payload.count }
        }
    }
}
