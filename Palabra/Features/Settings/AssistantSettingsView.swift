import SwiftUI

/// Settings → Assistant: how the Chat assistant answers and what it may do.
struct AssistantSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showDeleteChats = false

    var body: some View {
        @Bindable var env = environment
        Form {
            Section {
                Picker("Reply Length", selection: $env.assistantSettings.replyLength) {
                    Text("Concise").tag(AssistantSettings.ReplyLength.concise)
                    Text("Balanced").tag(AssistantSettings.ReplyLength.balanced)
                    Text("Detailed").tag(AssistantSettings.ReplyLength.detailed)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Replies")
            }
            .themedSection()

            Section {
                TextField("For example: always add an example sentence", text: instructionsBinding, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Your Instructions")
            } footer: {
                Text("Optional. The assistant follows these in every chat.")
            }
            .themedSection()

            Section {
                Picker("Read Photos With", selection: $env.assistantSettings.photoReading) {
                    Text("The AI Model").tag(AssistantSettings.PhotoReading.model)
                    Text("This Phone").tag(AssistantSettings.PhotoReading.onDevice)
                    Text("Phone First").tag(AssistantSettings.PhotoReading.onDeviceFirst)
                }
                .accessibilityIdentifier("chatPhotoReadingPicker")
            } header: {
                Text("Photos")
            } footer: {
                if environment.selectedModel?.acceptsImages == false {
                    Text("This model can't read photos, so photos sent in chat are read on this device.")
                } else {
                    photoReadingFooter
                }
            }
            .themedSection()

            Section {
                Toggle("Ask Before Making Changes", isOn: $env.assistantSettings.askBeforeChanging)
            } header: {
                Text("Changes")
            } footer: {
                if environment.assistantSettings.askBeforeChanging {
                    Text("Every change the assistant proposes waits for your Apply.")
                } else {
                    Text("Changes are applied as soon as the assistant proposes them. You can't undo them from the chat.")
                        .foregroundStyle(Theme.error)
                }
            }
            .themedSection()

            Section {
                ForEach(AssistantToolGroup.allCases, id: \.self) { group in
                    Toggle(isOn: groupBinding(group)) { Text(label(for: group)) }
                }
            } header: {
                Text("What the Assistant Can Use")
            } footer: {
                Text("Switch a part off and the assistant can no longer read or change it.")
            }
            .themedSection()

            Section {
                Button("Delete All Chats", role: .destructive) { showDeleteChats = true }
                    .disabled(environment.chat.conversations().isEmpty)
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all chats? This can't be undone.", isPresented: $showDeleteChats) {
            Button("Delete All", role: .destructive) { environment.deleteAllChats() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var photoReadingFooter: some View {
        switch environment.assistantSettings.photoReading {
        case .model:
            Text("The photo is sent to your AI model with your message. Best for handwriting and anything that is not plain printed text.")
        case .onDevice:
            Text("Your phone copies the text out of the photo and only that text is sent. The photo never leaves your phone, but it can miss handwriting and make mistakes with unusual layouts.")
        case .onDeviceFirst:
            Text("Your phone reads the photo first. If it finds no text, the photo is sent to your AI model instead.")
        }
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { environment.assistantSettings.customInstructions },
            set: { environment.assistantSettings.customInstructions = String($0.prefix(AssistantSettings.maxInstructionsLength)) }
        )
    }

    private func groupBinding(_ group: AssistantToolGroup) -> Binding<Bool> {
        Binding(
            get: { environment.assistantSettings.isEnabled(group) },
            set: { environment.assistantSettings.set(group, enabled: $0) }
        )
    }

    private func label(for group: AssistantToolGroup) -> LocalizedStringKey {
        switch group {
        case .library: return "Library and Progress"
        case .words: return "Adding and Organizing Words"
        case .study: return "Flashcards"
        case .review: return "Review List"
        }
    }
}
