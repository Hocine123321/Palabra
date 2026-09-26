import SwiftUI

/// The default, Apple-Watch-app-grid-inspired Library layout.
struct HoneycombGrid: View {
    let words: [Word]
    var onSelect: (Word) -> Void
    var onDeleteRequest: (Word) -> Void

    private let columns = 3
    private let tileSize: CGFloat = 100

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(Array(Honeycomb.rows(words, columns: columns).enumerated()), id: \.offset) { _, row in
                HStack(spacing: Theme.Spacing.md) {
                    if row.count == columns - 1 {
                        Spacer(minLength: tileSize / 2 + Theme.Spacing.md / 2)
                    }
                    ForEach(row, id: \.id) { word in
                        WordTile(word: word, size: tileSize)
                            .onTapGesture { onSelect(word) }
                            .contextMenu {
                                Button("Open") { onSelect(word) }
                                Button("Delete", role: .destructive) { onDeleteRequest(word) }
                            }
                    }
                    if row.count == columns - 1 {
                        Spacer(minLength: tileSize / 2 + Theme.Spacing.md / 2)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}

private struct WordTile: View {
    let word: Word
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Theme.tint(for: word.key))
            Text(word.spanish)
                .font(Theme.Font.serif(15))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .padding(8)
        }
        .frame(width: size, height: size)
        .scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
        .accessibilityLabel(word.spanish)
        .accessibilityAddTraits(.isButton)
    }
}
