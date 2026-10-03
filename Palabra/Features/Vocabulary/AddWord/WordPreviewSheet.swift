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
                case .queued:
                    VStack {
                        Spacer()
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "wifi.slash")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.inkSecondary)
                            Text("You're offline")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text("\"\(flow.inputWord)\" is queued and will be added automatically once you're back online.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(Theme.Spacing.lg)
                        Spacer()
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(flow.inputWord.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissTitle) { dismiss() }
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

    /// "Discard" would wrongly suggest a queued request is lost by closing the sheet.
    private var dismissTitle: LocalizedStringKey {
        if case .queued = flow.phase { return "Done" }
        return "Discard"
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
