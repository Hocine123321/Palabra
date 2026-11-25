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
                        Button { onSelect(word) } label: {
                            WordTile(word: word, size: tileSize)
                        }
                        .buttonStyle(PressScaleStyle())
                        .wordQuickActions(word, onOpen: { onSelect(word) }, onDeleteRequest: { onDeleteRequest(word) })
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
    /// Not private: a private property would make the memberwise init private too.
    var tints = WordTintSettings()
    @Environment(\.wordMastery) private var mastery
    @Environment(\.pinnedWordIDs) private var pinned

    /// A paper cutout: most tiles are circles, some rounded squares, picked from the word's key.
    private var kind: CutoutKind {
        WordKey.tintIndex(word.key + "#shape", count: 3) == 0 ? .roundedSquare : .circle
    }

    var body: some View {
        ZStack {
            CutoutShape(kind: kind).fill(tints.color(key: word.key, partOfSpeech: word.partOfSpeech))
            if let progress = mastery[word.id] {
                MasteryRing(kind: kind, fraction: progress).padding(5)
            }
            Text(word.spanish)
                .font(Theme.Font.tile)
                .foregroundStyle(Theme.onTint)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .padding(10)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if pinned.contains(word.id) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 22, height: 22)
                    .background(Theme.surface, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
        .accessibilityLabel(word.spanish)
        .accessibilityAddTraits(.isButton)
    }
}
