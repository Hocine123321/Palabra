import SwiftUI

/// Loading skeleton → four-section preview → Save/Replace, or a readable
/// failure with Retry and Edit word. Swipe-to-dismiss is disabled while an
/// unsaved result is showing, so it isn't lost by accident.
struct WordPreviewSheet: View {
    let flow: AddWordFlow
    @Environment(\.dismiss) private var dismiss
    var onSaved: (Word) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .loading:
                    LoadingPreview()
                case .loaded(let content):
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            if flow.interpretedDifferently {
                                Text("Interpreted as \"\(content.word)\"")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            WordContentView(content: content)
                        }
                        .padding(Theme.Spacing.md)
                    }
                case .failed(let error):
                    VStack {
                        Spacer()
                        ErrorBanner(
                            message: LocalizedStringKey(error.userMessage),
                            retryTitle: error.isRetryable ? "Retry" : nil,
                            onRetry: error.isRetryable ? { Task { await flow.retry() } } : nil,
                            secondaryTitle: "Edit word",
                            onSecondary: { dismiss() }
                        )
                        .padding(Theme.Spacing.md)
                        Spacer()
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(flow.inputWord.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                }
                if case .loaded = flow.phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle) {
                            if let saved = flow.save() {
                                onSaved(saved)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isUnsavedLoaded)
        .task { await flow.start() }
    }

    private var isUnsavedLoaded: Bool {
        if case .loaded = flow.phase { return true }
        return false
    }

    private var saveTitle: LocalizedStringKey {
        if case .regenerate = flow.mode { return "Replace" }
        return "Save"
    }
}

private struct LoadingPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Asking the AI…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(0..<4, id: \.self) { _ in
                    GlassSurface {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            LoadingSkeletonBlock(height: 16)
                            LoadingSkeletonBlock(height: 12)
                            LoadingSkeletonBlock(height: 12)
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
    }
}
