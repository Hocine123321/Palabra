import SwiftUI

/// An example sentence as tappable words: the word being read aloud lights up, words already in the
/// library are underlined, and tapping a word asks for its lookup. Spanish always lays out left to right.
struct SpokenSentenceView: View {
    let sentence: String
    /// The characters being spoken (from `SentenceSpeaker`), or nil.
    var spokenRange: NSRange?
    /// Accent-folded keys (`WordKey.search`) of the words in the library.
    var knownKeys: Set<String>
    var onTapWord: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(SentenceTokens.chunks(of: sentence).enumerated()), id: \.offset) { _, chunk in
                word(chunk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sentence))
    }

    @ViewBuilder
    private func word(_ chunk: SentenceChunk) -> some View {
        let spoken = SentenceTokens.isSpoken(chunk, at: spokenRange)
        let known = !chunk.core.isEmpty && knownKeys.contains(WordKey.search(chunk.core))
        let label = Text(verbatim: chunk.text)
            .underline(known, color: Theme.accentDeep)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .background(spoken ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .animation(Motion.reduced(Motion.quick), value: spoken)
        if chunk.core.isEmpty {
            label
        } else {
            label
                .contentShape(Rectangle())
                .onTapGesture { onTapWord(chunk.core) }
        }
    }
}
