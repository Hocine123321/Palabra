import SwiftUI

struct MissingAPIKeyPrompt: View {
    var onOpenSettings: () -> Void
    var body: some View {
        Button(action: onOpenSettings) {
            Label("Add your Google API key in Settings to add words", systemImage: "key")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassAccessory()
    }
}

struct MissingModelPrompt: View {
    var onOpenSettings: () -> Void
    var body: some View {
        Button(action: onOpenSettings) {
            Label("Choose a Google AI model in Settings", systemImage: "cpu")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassAccessory()
    }
}
