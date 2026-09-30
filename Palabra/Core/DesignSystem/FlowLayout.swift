import SwiftUI

/// Wraps its children onto new lines when they don't fit — used for
/// translation/similar-word chip rows and form lists. Mirrors for RTL: in a
/// right-to-left environment (Arabic App Language) rows fill from the
/// trailing edge instead of the leading one.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.sm
    @Environment(\.layoutDirection) private var layoutDirection

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            // Propose the available width so a long chip wraps its text onto
            // several lines instead of reporting an enormous single-line size.
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            maxX = max(maxX, origin.x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        // Never claim more width than we were offered: an over-wide answer here is
        // what used to stretch the whole word screen past the display edge.
        return CGSize(width: min(maxX, maxWidth), height: origin.y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let isRTL = layoutDirection == .rightToLeft
        var origin = CGPoint(x: isRTL ? bounds.maxX : bounds.minX, y: bounds.origin.y)
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let wouldOverflow = isRTL ? (origin.x - size.width < bounds.minX) : (origin.x + size.width > bounds.maxX)
            let atLineStart = isRTL ? (origin.x < bounds.maxX) : (origin.x > bounds.minX)
            if wouldOverflow, atLineStart {
                origin.x = isRTL ? bounds.maxX : bounds.minX
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            if isRTL {
                subview.place(at: CGPoint(x: origin.x - size.width, y: origin.y), proposal: ProposedViewSize(width: size.width, height: size.height))
                origin.x -= size.width + spacing
            } else {
                subview.place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))
                origin.x += size.width + spacing
            }
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in Chip(text: item) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
