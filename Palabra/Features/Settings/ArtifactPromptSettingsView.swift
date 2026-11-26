import SwiftUI

/// Settings → Artifacts → Prompts: the rules that make an artifact compatible with Palabra, for the prompt copied into another
/// AI and for the in-app AI. Everything starts as the built-in text; changing a piece never touches the rest, and "Replace the
/// whole prompt" is the advanced way to write all of it.
struct ArtifactPromptSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var prompt: ArtifactPromptSettings { environment.artifactSettings.prompt }

    var body: some View {
        @Bindable var env = environment
        Form {
            Section {
                NavigationLink {
                    PromptTextEditorView(
                        title: "Intro",
                        help: "What the other AI is told it is building. Leave it empty to use the built-in intro.",
                        text: Binding(get: { prompt.intro ?? ArtifactPrompts.defaultIntro }, set: { env.artifactSettings.prompt.intro = $0 == ArtifactPrompts.defaultIntro ? nil : $0 }),
                        builtIn: ArtifactPrompts.defaultIntro
                    )
                } label: {
                    row("Intro", status: prompt.activeIntro == nil ? "Built-in" : "Edited")
                }
                ForEach(ArtifactPrompts.Rule.allCases) { rule in
                    NavigationLink {
                        PromptRuleEditorView(rule: rule)
                    } label: {
                        row(rule.title, status: ruleStatus(rule))
                    }
                    .accessibilityIdentifier("promptRule.\(rule.rawValue)")
                }
                NavigationLink {
                    PromptTextEditorView(
                        title: "Extra Rules",
                        help: "Your own rules, one per line. They are added after the built-in ones.",
                        text: Binding(get: { prompt.extraRules }, set: { env.artifactSettings.prompt.extraRules = $0 }),
                        builtIn: nil
                    )
                } label: {
                    row("Extra Rules", status: prompt.activeExtraRules.isEmpty ? "None" : "Edited")
                }
                .accessibilityIdentifier("promptExtraRules")
                Toggle("Include Capability List", isOn: Binding(get: { prompt.includeCapabilities }, set: { env.artifactSettings.prompt.includeCapabilities = $0 }))
            } header: {
                Text("Prompt for Another AI")
            } footer: {
                Text("What \"Copy artifact prompt rules\" gives Claude, ChatGPT or any other AI. Switch a rule off, reword it, or add your own. The capability list tells it what the page can ask Palabra for.")
            }
            .themedSection()

            Section {
                NavigationLink {
                    PromptTextEditorView(
                        title: "In-App Extra Rules",
                        help: "Your own rules for the in-app AI, one per line. They are added after the built-in ones.",
                        text: Binding(get: { prompt.inAppExtraRules }, set: { env.artifactSettings.prompt.inAppExtraRules = $0 }),
                        builtIn: nil
                    )
                } label: {
                    row("Extra Rules", status: prompt.activeInAppExtraRules.isEmpty ? "None" : "Edited")
                }
                .accessibilityIdentifier("promptInAppExtraRules")
            } header: {
                Text("In-App AI")
            } footer: {
                Text("Added to the instruction Palabra sends with every request it makes for an artifact.")
            }
            .themedSection()

            Section {
                NavigationLink {
                    PromptTemplateEditorView(
                        title: "Replace the Whole Prompt",
                        builtIn: ArtifactPrompts.externalTemplateText,
                        placeholders: ArtifactPrompts.externalPlaceholders,
                        note: "Your text replaces the built-in prompt. The built-in rules, intro and capability list are only used where you put their placeholders. If you leave out {{REQUEST}}, the request is added at the end.",
                        template: Binding(get: { prompt.template }, set: { env.artifactSettings.prompt.template = $0 })
                    )
                } label: {
                    row("Prompt for Another AI", status: prompt.activeTemplate == nil ? "Built-in" : "Replaced")
                }
                .accessibilityIdentifier("promptReplaceExternal")
                NavigationLink {
                    PromptTemplateEditorView(
                        title: "Replace the In-App Instruction",
                        builtIn: ArtifactPrompts.inAppTemplateText,
                        placeholders: ArtifactPrompts.inAppPlaceholders,
                        note: "Palabra reads the AI's answer by a fixed format. If you leave out {{OUTPUT_FORMAT}} (or {{APP_RULES}} while interactive apps are on), it is added at the end so artifacts keep working.",
                        template: Binding(get: { prompt.inAppTemplate }, set: { env.artifactSettings.prompt.inAppTemplate = $0 })
                    )
                } label: {
                    row("In-App Instruction", status: prompt.activeInAppTemplate == nil ? "Built-in" : "Replaced")
                }
                .accessibilityIdentifier("promptReplaceInApp")
            } header: {
                Text("Advanced")
            } footer: {
                Text("For full control. A prompt that breaks the page rules makes artifacts that Palabra refuses to run.")
            }
            .themedSection()

            Section {
                NavigationLink("Preview the Prompt for Another AI") {
                    PromptPreviewView(title: "Prompt for Another AI", text: externalPreview)
                }
                NavigationLink("Preview the In-App Instruction") {
                    PromptPreviewView(title: "In-App Instruction", text: inAppPreview)
                }
                Button("Reset All Prompt Changes", role: .destructive) {
                    env.artifactSettings.prompt = ArtifactPromptSettings()
                }
                .disabled(prompt.isDefault)
                .accessibilityIdentifier("promptResetAll")
            } header: {
                Text("Check")
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Prompts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, status: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            Text(LocalizedStringKey(status)).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func ruleStatus(_ rule: ArtifactPrompts.Rule) -> String {
        let override = prompt.override(for: rule.rawValue)
        if !override.enabled { return "Off" }
        return override.text == nil ? "Built-in" : "Edited"
    }

    private var externalPreview: String {
        ArtifactPrompts.exportPrompt(
            userPrompt: "(your request goes here)", registry: environment.capabilities, language: environment.aiLanguage,
            maxKB: environment.artifactSettings.externalMaxKB, config: prompt
        )
    }

    private var inAppPreview: String {
        let settings = environment.artifactSettings
        return ArtifactPrompts.systemInstruction(
            registry: environment.capabilities, language: environment.aiLanguage,
            allowedKinds: settings.allowAppArtifacts ? [.spec, .app] : [.spec], maxKB: settings.maxOutputKB, config: prompt
        )
    }
}

/// One built-in rule: switch it off, or reword it.
private struct PromptRuleEditorView: View {
    let rule: ArtifactPrompts.Rule
    @Environment(AppEnvironment.self) private var environment

    private var override: ArtifactPromptSettings.RuleOverride {
        environment.artifactSettings.prompt.override(for: rule.rawValue)
    }

    var body: some View {
        @Bindable var env = environment
        Form {
            Section {
                Toggle("Use This Rule", isOn: Binding(
                    get: { override.enabled },
                    set: { env.artifactSettings.prompt.setRule(rule.rawValue, enabled: $0, text: override.text) }
                ))
            }
            .themedSection()
            Section {
                TextEditor(text: Binding(
                    get: { override.text ?? rule.template },
                    set: { new in
                        env.artifactSettings.prompt.setRule(rule.rawValue, enabled: override.enabled, text: new == rule.template ? nil : new)
                    }
                ))
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 200)
                .disabled(!override.enabled)
            } header: {
                Text("Wording")
            } footer: {
                Text("{{MAX_SIZE}} and {{LANGUAGE}} are filled in from your settings.")
            }
            .themedSection()
            Section {
                Button("Use Built-in Wording") {
                    env.artifactSettings.prompt.setRule(rule.rawValue, enabled: override.enabled, text: nil)
                }
                .disabled(override.text == nil)
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle(LocalizedStringKey(rule.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A free-text piece (the intro, extra rules).
private struct PromptTextEditorView: View {
    let title: String
    let help: String
    @Binding var text: String
    let builtIn: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 260)
            } footer: {
                Text(LocalizedStringKey(help))
            }
            .themedSection()
            if let builtIn {
                Section {
                    Button("Use Built-in Text") { text = builtIn }
                        .disabled(text == builtIn)
                }
                .themedSection()
            } else {
                Section {
                    Button("Clear", role: .destructive) { text = "" }
                        .disabled(text.isEmpty)
                }
                .themedSection()
            }
        }
        .glassScreen()
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Replaces a whole prompt. Starts from the built-in text with its placeholders, so it is edited rather than written from nothing.
private struct PromptTemplateEditorView: View {
    let title: String
    let builtIn: String
    let placeholders: [String]
    let note: String
    @Binding var template: String?

    var body: some View {
        Form {
            Section {
                Toggle("Replace the Built-in Prompt", isOn: Binding(
                    get: { template != nil },
                    set: { template = $0 ? builtIn : nil }
                ))
            } footer: {
                Text(LocalizedStringKey(note))
            }
            .themedSection()
            if template != nil {
                Section {
                    TextEditor(text: Binding(get: { template ?? "" }, set: { template = $0 }))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 320)
                } header: {
                    Text("Prompt")
                } footer: {
                    Text(verbatim: placeholders.joined(separator: "  "))
                        .font(.system(.caption, design: .monospaced))
                }
                .themedSection()
                Section {
                    Button("Start Again From Built-in Text") { template = builtIn }
                        .disabled(template == builtIn)
                }
                .themedSection()
            }
        }
        .glassScreen()
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The prompt exactly as it would be sent (the request is a stand-in).
private struct PromptPreviewView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
        }
        .background { ScreenBackdrop() }
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            }
        }
    }
}
