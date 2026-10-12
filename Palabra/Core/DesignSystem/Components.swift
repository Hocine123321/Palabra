import SwiftUI

struct Chip: View {
    private let label: Text
    private let tint: Color?

    /// Verbatim text — for AI-generated or user-entered content (a word,
    /// a part of speech, an example's context tag) that must never be run
    /// through the localization table.
    init(text: String, tint: Color? = nil) {
        label = Text(text)
        self.tint = tint
    }

    /// Localized app-chrome text (e.g. a fixed jump-bar section label).
    init(titleKey: LocalizedStringKey, tint: Color? = nil) {
        label = Text(titleKey)
        self.tint = tint
    }

    var body: some View {
        label
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.sm + 4)
            .padding(.vertical, 6)
            .foregroundStyle(tint == nil ? Theme.inkSecondary : Theme.onTint)
            .background {
                // A chip sits on a card or on glass, so it is a flat fill, never glass.
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(tint ?? Theme.fill.opacity(0.8))
            }
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.error)
            HStack(spacing: Theme.Spacing.sm) {
                if let retryTitle, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.error.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.onTint)
                .frame(width: 76, height: 76)
                .background(Theme.accent, in: CutoutShape(kind: .roundedSquare))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Font.heading)
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
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(Theme.inkSecondary.opacity(pulse ? 0.08 : 0.16))
            .frame(height: height)
            .onAppear {
                Motion.animate(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
