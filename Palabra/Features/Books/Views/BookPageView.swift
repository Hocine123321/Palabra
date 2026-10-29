import SwiftUI

/// One numbered page of a book: a title block, the lesson's blocks, and the page number at the foot.
struct BookPageView: View {
    let page: BookPage

    @Environment(\.bookPalette) private var palette

    var body: some View {
        let scope = PageScope(page: page)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                ForEach(Array(page.page.blocks.enumerated()), id: \.offset) { entry in
                    BlockView(block: entry.element, scope: scope, index: entry.offset)
                }
                Text(verbatim: "— \(page.number) —")
                    .font(palette.font(.footnote))
                    .foregroundStyle(palette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.md)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            // Room for the reading controls floating over the bottom of the page.
            .padding(.bottom, 170)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .leading) {
            // The spine: a soft shade down the binding edge (the right edge in a right-to-left book).
            LinearGradient(colors: [palette.ink.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("bookPage.\(page.number)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            Text(verbatim: page.lessonTitle)
                .font(palette.font(.caption, weight: .semibold))
                .foregroundStyle(palette.inkSecondary)
            Text(verbatim: page.page.title)
                .font(palette.font(.title, weight: .bold))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let date = page.page.dateLabel {
                Text(verbatim: date)
                    .font(palette.font(.caption))
                    .foregroundStyle(palette.inkSecondary)
            }
            VStack(spacing: 2) {
                Rectangle().fill(palette.accent).frame(height: 2)
                Rectangle().fill(palette.rule).frame(height: 1)
            }
            .padding(.top, Theme.Spacing.xs)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
