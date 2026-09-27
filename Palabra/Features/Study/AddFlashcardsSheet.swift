import SwiftUI

/// Paste notes (any subject) → AI drafts flashcards → pick which to keep → save.
struct AddFlashcardsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String
    @State private var notes = ""
    @State private var flow: AddFlashcardsFlow?

    var onSaved: (Int) -> Void

    init(defaultSubject: String = "", onSaved: @escaping (Int) -> Void) {
        _subject = State(initialValue: defaultSubject)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Group {
                if let flow {
                    switch flow.phase {
                    case .idle, .loading:
                        loadingView
                    case .loaded(let drafts):
                        draftList(flow: flow, drafts: drafts)
                    case .failed(let error):
                        failureView(flow: flow, error: error)
                    }
                } else {
                    inputForm
                }
            }
            .background(Theme.background)
            .navigationTitle("Add Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let flow, case .loaded = flow.phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save (\(flow.selected.count))") {
                            let count = flow.save(subject: subject)
                            onSaved(count)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(flow.selected.isEmpty)
                    }
                }
            }
        }
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !environment.hasAPIKey {
                    MissingAPIKeyPrompt(onOpenSettings: { environment.router.openSettings() })
                } else if environment.selectedModel == nil {
                    MissingModelPrompt(onOpenSettings: { environment.router.openSettings() })
                }
                GlassSurface {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Subject").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        TextField("e.g. Biology, French Revolution", text: $subject)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(Theme.Spacing.md)
                }
                GlassSurface {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Paste your class notes").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        TextEditor(text: $notes)
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(Theme.Spacing.md)
                }
                Button {
                    let newFlow = AddFlashcardsFlow(environment: environment)
                    flow = newFlow
                    Task { await newFlow.generate(subject: subject, notes: notes) }
                } label: {
                    Text("Generate Flashcards").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !environment.hasAPIKey || environment.selectedModel == nil)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            ProgressView()
            Text("Reading your notes…").font(.subheadline).foregroundStyle(Theme.inkSecondary)
            Spacer()
        }
    }

    private func draftList(flow: AddFlashcardsFlow, drafts: [FlashcardDraft]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Tap a card to keep or skip it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                    let isSelected = flow.selected.contains(index)
                    GlassSurface {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack {
                                Text(draft.front).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkSecondary)
                            }
                            Text(draft.back).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            if let hint = draft.hint, !hint.isEmpty {
                                Text("Hint: \(hint)").font(.caption).foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected { flow.selected.remove(index) } else { flow.selected.insert(index) }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func failureView(flow: AddFlashcardsFlow, error: AIError) -> some View {
        VStack {
            Spacer()
            ErrorBanner(
                message: LocalizedStringKey(error.userMessage),
                retryTitle: error.isRetryable ? "Retry" : nil,
                onRetry: error.isRetryable ? { Task { await flow.generate(subject: subject, notes: notes) } } : nil,
                secondaryTitle: "Edit notes",
                onSecondary: { self.flow = nil }
            )
            .padding(Theme.Spacing.md)
            Spacer()
        }
    }
}
