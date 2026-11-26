import SwiftUI

/// The persistent bottom glass input capsule for adding a word. While the field is being typed in, a second capsule
/// with the Spanish letters sits right above it (not in the keyboard toolbar: on recent iOS that floats over the field).
struct AddWordBar: View {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if focused {
                AccentKeyRow { text.append($0) }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .glassCapsule()
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xs)
                    .transition(.opacity)
            }
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .accessibilityHidden(true)
                TextField("Add a Spanish word…", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
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
        }
        .animation(Motion.quick, value: focused)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}
