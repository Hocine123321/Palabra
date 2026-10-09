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
        .creamScreen()
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all chats? This can't be undone.", isPresented: $showDeleteChats) {
            Button("Delete All", role: .destructive) { environment.deleteAllChats() }
            Button("Cancel", role: .cancel) {}
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
