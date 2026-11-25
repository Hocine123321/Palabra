import SwiftUI

/// A row of Spanish letters and punctuation (á é í ó ú ñ ü ¿ ¡) for people typing on an English keyboard.
/// Used above the keyboard in the add-word bar and under the exam's "type in Spanish" field.
struct AccentKeyRow: View {
    var onInsert: (String) -> Void

    static let letters = ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Self.letters, id: \.self) { letter in
                Button { onInsert(letter) } label: {
                    Text(verbatim: letter)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
