import SwiftUI

/// The persistent bottom glass input capsule for adding a word.
struct AddWordBar: View {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            TextField("Add a Spanish word…", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onSubmit)
            Button(action: onSubmit) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accentDeep)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add word")
            .accessibilityIdentifier("addWordButton")
        }
        .glassAccessory()
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}
