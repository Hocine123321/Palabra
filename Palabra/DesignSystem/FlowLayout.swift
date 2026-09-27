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
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            maxX = max(maxX, origin.x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: origin.y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let isRTL = layoutDirection == .rightToLeft
        var origin = CGPoint(x: isRTL ? bounds.maxX : bounds.minX, y: bounds.origin.y)
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let wouldOverflow = isRTL ? (origin.x - size.width < bounds.minX) : (origin.x + size.width > bounds.maxX)
            let atLineStart = isRTL ? (origin.x < bounds.maxX) : (origin.x > bounds.minX)
            if wouldOverflow, atLineStart {
                origin.x = isRTL ? bounds.maxX : bounds.minX
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            if isRTL {
                subview.place(at: CGPoint(x: origin.x - size.width, y: origin.y), proposal: .unspecified)
                origin.x -= size.width + spacing
            } else {
                subview.place(at: origin, proposal: .unspecified)
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
            ForEach(items, id: \.self) { Chip(text: $0) }
        }
    }
}
