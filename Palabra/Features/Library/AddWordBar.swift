import SwiftUI

/// The persistent bottom glass input capsule for adding a word.
struct AddWordBar: View {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: Theme.Radius.pill) {
            HStack {
                TextField("Add a Spanish word…", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                Button(action: onSubmit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("addWordButton")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}
