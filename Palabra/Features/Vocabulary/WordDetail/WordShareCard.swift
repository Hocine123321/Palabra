import SwiftUI

/// The picture shared by "Share as Image": the headword on its cutout, its meanings and one example.
struct WordShareCard: View {
    let content: WordContent
    let tint: Color

    var body: some View {
        CutoutCard(tint: tint) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !content.forms.partOfSpeech.isEmpty {
                    Chip(text: content.forms.partOfSpeech, tint: Color.white.opacity(0.45))
                }
                Text(verbatim: content.word)
                    .font(Theme.Font.display)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if !content.meaning.translations.isEmpty {
                    FlowLayout {
                        ForEach(Array(content.meaning.translations.prefix(4).enumerated()), id: \.offset) { _, translation in
                            Chip(text: translation, tint: Color.white.opacity(0.45))
                        }
                    }
                }
                if let example = content.examples.first {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: example.spanish).font(.subheadline.weight(.semibold))
                        Text(verbatim: example.translation).font(.footnote).opacity(0.7)
                    }
                    .lineLimit(6)
                }
                Text(verbatim: "Palabra")
                    .font(.caption.weight(.bold))
                    .opacity(0.5)
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 340, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.paper)
        .environment(\.colorScheme, .light)
    }

    /// Draws the card to an image for the share sheet (nil if rendering fails).
    @MainActor
    static func render(content: WordContent, tint: Color) -> Image? {
        let renderer = ImageRenderer(content: WordShareCard(content: content, tint: tint))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
