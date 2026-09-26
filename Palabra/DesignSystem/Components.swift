import SwiftUI

struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
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
struct ErrorBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String? = "Retry"
    var onRetry: (() -> Void)?
    var secondaryTitle: String?
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
    let title: String
    let message: String

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
