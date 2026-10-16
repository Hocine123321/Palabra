import SwiftUI

extension SolvePhotoMode: Identifiable {
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .sendToGemini: return "Send photo to Gemini"
        case .readText: return "Read text, then solve"
        case .readOnDevice: return "Read text on this device"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .sendToGemini:
            return "Gemini looks at the photo itself, copies the whole problem and solves it in one step. Best for handwriting, several parts and diagrams. Needs your API key."
        case .readText:
            return "Gemini copies the problem as text first (this device does it if Gemini can't). You check the text, then tap Solve."
        case .readOnDevice:
            return "The photo never leaves this device. Reading is weaker on handwriting and maths notation, so check the text before you solve."
        }
    }
}

/// Everything about the Solve tab that can be tweaked: how photos are handled, what solves a problem, which model it uses,
/// and the optional Wolfram|Alpha App ID.
struct SolveSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showModelPicker = false

    var body: some View {
        @Bindable var tool = environment.solve
        Form {
            Section {
                Picker("Photos", selection: $tool.settings.photoMode) {
                    ForEach(SolvePhotoMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("photoModePicker")
            } header: {
                Text("Photos")
            } footer: {
                Text(tool.settings.photoMode.detail)
            }
            .themedSection()

            if !environment.hasAPIKey, tool.settings.photoMode != .readOnDevice {
                Section {
                    Label("Add your API key in Settings so Gemini can read and solve photos.", systemImage: "key.slash")
                        .foregroundStyle(Theme.error)
                }
                .themedSection()
            }

            Section {
                Toggle("Solve on this device first", isOn: $tool.settings.useOnDeviceEngine)
                    .accessibilityIdentifier("onDeviceEngineToggle")
                Button {
                    showModelPicker = true
                } label: {
                    HStack {
                        Text("Gemini Model").foregroundStyle(Theme.ink)
                        Spacer()
                        ModelValueLabel(id: tool.settings.modelID, placeholder: "Same as your main model")
                    }
                }
                .accessibilityIdentifier("solveModelRow")
            } header: {
                Text("Solving")
            } footer: {
                Text("The on-device engine is instant and works offline for standard algebra and calculus. Turn it off to send every typed problem to Gemini. The model is used for photos, harder problems and steps.")
            }
            .themedSection()

            Section {
                WolframKeyField()
                if tool.hasKey {
                    Text("About \(tool.callsThisMonth) of \(SolveUsage.freeMonthlyCalls) free solves used this month")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            } header: {
                Text("Wolfram|Alpha (optional)")
            } footer: {
                Text("Optional. A Wolfram|Alpha App ID adds Wolfram's answers for typed problems your device can't solve.")
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Solve Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(
                title: "Choose a Solve Model",
                catalogue: environment.catalogue,
                selection: $tool.settings.modelID,
                canTest: true,
                automaticTitle: "Same as your main model"
            )
        }
    }
}
