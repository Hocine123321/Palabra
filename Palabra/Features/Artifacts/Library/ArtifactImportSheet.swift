import SwiftUI

/// Where the answer from another AI (Claude, ChatGPT) is pasted. `onUse` gets the raw text; the draft model parses it.
struct ArtifactImportSheet: View {
    var onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(Theme.Spacing.sm)
                        .accessibilityIdentifier("artifactImportField")
                    if text.isEmpty {
                        Text("Paste the answer here")
                            .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                            .padding(.horizontal, Theme.Spacing.sm + 5)
                            .padding(.vertical, Theme.Spacing.sm + 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .innerFill(cornerRadius: Theme.Radius.medium)
                .padding(Theme.Spacing.sm)
                .glassCard()
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Paste from clipboard") {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("artifactImportPasteButton")
                    Button {
                        onUse(text)
                        dismiss()
                    } label: {
                        Text("Use this answer")
                    }
                    .buttonStyle(.primary)
                    .disabled(isEmpty)
                    .accessibilityIdentifier("artifactImportUseButton")
                }
            }
            .padding(Theme.Spacing.md)
            .background(ScreenBackdrop())
            .navigationTitle("Paste Claude's answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
