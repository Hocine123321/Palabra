import SwiftUI

/// Liquid Glass on iOS 26+, a hand-built glass (material, sheen, specular rim,
/// soft lift) below it. Glass floats: bars, accessories, sheets, controls.
/// Content inside glass sits on `Theme.fill`, never on more glass.
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content.background(GlassBackground(cornerRadius: cornerRadius, tint: tint))
    }
}

/// The glass material alone, for use as a `.background`.
struct GlassBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    var tint: Color?

    var body: some View {
        if #available(iOS 26, *) {
            #if compiler(>=6.2)
            if let tint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(tint.opacity(0.35)), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            #else
            fallback
            #endif
        } else {
            fallback
        }
    }

    private var fallback: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay { if let tint { shape.fill(tint.opacity(0.18)) } }
            .overlay {
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.7, y: 0.6)
                ))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.65), Color.white.opacity(0.06), Color.white.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}
