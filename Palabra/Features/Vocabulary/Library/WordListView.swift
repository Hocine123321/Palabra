import SwiftUI

/// The Readability Library layout: a conventional scannable list.
struct WordListView: View {
    let words: [Word]
    var onSelect: (Word) -> Void
    var onDeleteRequest: (Word) -> Void

    var body: some View {
        LazyVStack(spacing: Theme.Spacing.sm) {
            ForEach(words, id: \.id) { word in
                Button { onSelect(word) } label: {
                    GlassSurface(cornerRadius: 16) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(Theme.tint(for: word.key))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.spanish)
                                    .font(Theme.Font.serif(18))
                                    .foregroundStyle(Theme.ink)
                                if !word.translation.isEmpty {
                                    Text(word.translation)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            Spacer()
                            if !word.partOfSpeech.isEmpty { Chip(text: word.partOfSpeech) }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { onDeleteRequest(word) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}
