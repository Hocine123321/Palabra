import SwiftUI

struct Chip: View {
    private let label: Text

    /// Verbatim text — for AI-generated or user-entered content (a word,
    /// a part of speech, an example's context tag) that must never be run
    /// through the localization table.
    init(text: String) {
        label = Text(text)
    }

    /// Localized app-chrome text (e.g. a fixed jump-bar section label).
    init(titleKey: LocalizedStringKey) {
        label = Text(titleKey)
    }

    var body: some View {
        label
            .font(.caption.weight(.medium))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Theme.surface, in: Capsule())
            .foregroundStyle(Theme.inkSecondary)
            .overlay(Capsule().strokeBorder(Theme.inkSecondary.opacity(0.15)))
    }
}

/// Readable-reason error card with an optional retry and a second action
/// (e.g. "Edit word", "Open Settings").
///
/// `message` is typed `LocalizedStringKey` (not `String`) so that callers
/// passing pre-built text — like `AIError.userMessage` — actually get
/// looked up in Localizable.strings; a plain `String` would render verbatim
/// and silently ignore the current App Language.
struct ErrorBanner: View {
    let message: LocalizedStringKey
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: LocalizedStringKey? = "Retry"
    var onRetry: (() -> Void)?
    var secondaryTitle: LocalizedStringKey?
    var onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(message, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.error)
            HStack(spacing: Theme.Spacing.sm) {
                if let retryTitle, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.error.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(Theme.Font.serif(20))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingSkeletonBlock: View {
    var height: CGFloat = 14
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.inkSecondary.opacity(pulse ? 0.08 : 0.16))
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
