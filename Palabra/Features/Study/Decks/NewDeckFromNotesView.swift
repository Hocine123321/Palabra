import SwiftUI

struct NewDeckFromNotesView: View {
    var onSaved: (UUID) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: NotesDeckModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { Color.clear }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            if model == nil { model = NotesDeckModel(environment: environment) }
        }
    }

    @ViewBuilder
    private func content(_ model: NotesDeckModel) -> some View {
        switch model.phase {
        case .input:
            inputForm(model: model)
        case .generating:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Generating cards…").foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            VStack(spacing: Theme.Spacing.md) {
                ErrorBanner(
                    message: LocalizedStringKey(error.userMessage),
                    onRetry: { Task { await model.generate() } },
                    secondaryTitle: "Edit Notes",
                    onSecondary: { model.backToInput() }
                )
                Spacer()
            }
            .padding(Theme.Spacing.md)
        case .preview:
            previewList(model: model)
        }
    }

    private func inputForm(model: NotesDeckModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Paste your notes and the AI will turn them into flashcards.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            TextEditor(text: $model.notes)
                .frame(minHeight: 220)
                .padding(Theme.Spacing.sm)
                .glassCard()
                .accessibilityIdentifier("notesField")
            Button {
                Task { await model.generate() }
            } label: {
                Text("Generate Cards")
            }
            .buttonStyle(.primary)
            .disabled(!model.canGenerate)
            .accessibilityIdentifier("generateCardsButton")
            Spacer()
        }
        .padding(Theme.Spacing.md)
    }

    private func previewList(model: NotesDeckModel) -> some View {
        @Bindable var model = model
        return List {
            Section("Deck Name") {
                TextField("Deck name", text: $model.title)
                    .accessibilityIdentifier("deckNameField")
            }
            .themedSection()
            Section("Cards") {
                ForEach($model.drafts) { $draft in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TextField("Front", text: $draft.front, axis: .vertical).font(.headline)
                        TextField("Back", text: $draft.back, axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .onDelete { model.deleteDrafts(at: $0) }
            }
            .themedSection()
            Section {
                Button("Save Deck") {
                    if let id = model.save() {
                        onSaved(id)
                        dismiss()
                    }
                }
                .disabled(!model.canSave)
                .accessibilityIdentifier("saveDeckButton")
            }
            .themedSection()
        }
        .creamScreen()
    }
}
