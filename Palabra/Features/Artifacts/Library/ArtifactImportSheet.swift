import SwiftUI
import UniformTypeIdentifiers

/// Where a page made by another AI (Claude, ChatGPT) is pasted, or chosen as a file. `onUse` gets the raw text; the draft model
/// parses it. A file is read as text into the same field, so the person sees what will be used before tapping the button.
struct ArtifactImportSheet: View {
    var onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showFiles = false
    @State private var fileError = false

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
                        Text("Paste the HTML page here")
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
                if fileError {
                    Text("That file couldn't be read as text.")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("artifactImportFileError")
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Paste from clipboard") {
                        if let pasted = UIPasteboard.general.string { text = pasted; fileError = false }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("artifactImportPasteButton")
                    Button("Choose file") { showFiles = true }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .accessibilityIdentifier("artifactImportFileButton")
                }
                Button {
                    onUse(text)
                    dismiss()
                } label: {
                    Text("Use this page")
                }
                .buttonStyle(.primary)
                .disabled(isEmpty)
                .accessibilityIdentifier("artifactImportUseButton")
            }
            .padding(Theme.Spacing.md)
            .background(ScreenBackdrop())
            .navigationTitle("Upload/paste artifact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.html, .plainText, .json, .text]) { result in
                guard case .success(let url) = result, let loaded = Self.readText(url) else { fileError = true; return }
                text = loaded
                fileError = false
            }
        }
    }

    /// The text of a file the person picked in Files (it needs security-scoped access), or nil when it is not readable text or
    /// is larger than an artifact may be.
    static func readText(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= ArtifactImport.maxInputBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
