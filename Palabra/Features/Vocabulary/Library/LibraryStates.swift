import SwiftUI

struct MissingAPIKeyPrompt: View {
    var onOpenSettings: () -> Void
    var body: some View {
        Button(action: onOpenSettings) {
            Label("Add your Google API key in Settings to add words", systemImage: "key")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }
}

struct MissingModelPrompt: View {
    var onOpenSettings: () -> Void
    var body: some View {
        Button(action: onOpenSettings) {
            Label("Choose a Google AI model in Settings", systemImage: "cpu")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }
}
