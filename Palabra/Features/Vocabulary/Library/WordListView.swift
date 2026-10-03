import SwiftUI

/// The Readability Library layout: a conventional scannable list.
struct WordListView: View {
    let words: [Word]
    var showTags: Bool = false
    var onSelect: (Word) -> Void
    var onDeleteRequest: (Word) -> Void

    var body: some View {
        LazyVStack(spacing: Theme.Spacing.sm) {
            ForEach(words, id: \.id) { word in
                Button { onSelect(word) } label: {
                    GlassSurface(cornerRadius: Theme.Radius.medium) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(Theme.tint(for: word.key))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.spanish)
                                    .font(Theme.Font.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                if !word.translation.isEmpty {
                                    Text(word.translation)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                if showTags, !word.tags.isEmpty {
                                    Text(verbatim: word.tags.map { "#\($0)" }.joined(separator: "  "))
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                        .lineLimit(2)
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
