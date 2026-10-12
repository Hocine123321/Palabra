import SwiftUI

/// The cutout vocabulary: flat paper shapes that sit behind glass.
enum CutoutKind {
    case circle, roundedSquare, quarter, pill, arch
}

struct CutoutShape: Shape {
    var kind: CutoutKind

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        switch kind {
        case .circle:
            return Path(ellipseIn: rect)
        case .roundedSquare:
            return Path(roundedRect: rect, cornerRadius: min(w, h) * 0.28, style: .continuous)
        case .pill:
            return Path(roundedRect: rect, cornerRadius: min(w, h) / 2, style: .continuous)
        case .quarter:
            return UnevenRoundedRectangle(
                topLeadingRadius: min(w, h), bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0,
                style: .continuous
            ).path(in: rect)
        case .arch:
            return UnevenRoundedRectangle(
                topLeadingRadius: w / 2, bottomLeadingRadius: w * 0.13, bottomTrailingRadius: w * 0.13, topTrailingRadius: w / 2,
                style: .continuous
            ).path(in: rect)
        }
    }
}

/// The ground behind every screen: warm neutral with a few muted cutouts that
/// the glass above bends. Decorative, so hidden from accessibility.
struct ScreenBackdrop: View {
    enum Style {
        /// One orange cutout and a small sage one. Lists and forms.
        case calm
        /// More shapes. Hubs, onboarding, empty states.
        case rich
    }

    var style: Style = .calm
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let strong = scheme == .dark ? 0.42 : 0.62
            let soft = scheme == .dark ? 0.30 : 0.50
            ZStack(alignment: .topLeading) {
                Theme.background
                CutoutShape(kind: .circle)
                    .fill(Theme.accent.opacity(strong))
                    .frame(width: w * 0.8, height: w * 0.8)
                    .offset(x: w * 0.4, y: -w * 0.34)
                CutoutShape(kind: .circle)
                    .fill(Theme.tileTints[1].opacity(soft))
                    .frame(width: w * 0.5, height: w * 0.5)
                    .offset(x: -w * 0.28, y: h * 0.78)
                if style == .rich {
                    CutoutShape(kind: .circle)
                        .fill(Theme.tileTints[2].opacity(soft))
                        .frame(width: w * 0.62, height: w * 0.62)
                        .offset(x: -w * 0.34, y: h * 0.30)
                    CutoutShape(kind: .quarter)
                        .fill(Theme.tileTints[4].opacity(soft))
                        .frame(width: w * 0.5, height: w * 0.5)
                        .offset(x: w * 0.72, y: h * 0.5)
                    CutoutShape(kind: .pill)
                        .fill(Theme.tileTints[3].opacity(soft))
                        .frame(width: w * 0.6, height: w * 0.22)
                        .rotationEffect(.degrees(-12))
                        .offset(x: w * 0.5, y: h * 0.86)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A hero card: a muted tint with paper cutouts, ink text on top. Word hero,
/// flashcard face, Solve answer paper.
struct CutoutCard<Content: View>: View {
    var tint: Color
    var cornerRadius: CGFloat = Theme.Radius.sheet
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Theme.onTint)
            .background {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height * 1.4)
                    ZStack(alignment: .topLeading) {
                        tint
                        CutoutShape(kind: .circle)
                            .fill(Color.white.opacity(0.30))
                            .frame(width: side * 0.75, height: side * 0.75)
                            .offset(x: proxy.size.width - side * 0.45, y: -side * 0.30)
                        CutoutShape(kind: .pill)
                            .fill(Color.black.opacity(0.07))
                            .frame(width: side * 0.5, height: side * 0.18)
                            .rotationEffect(.degrees(-14))
                            .offset(x: side * 0.08, y: proxy.size.height * 0.45)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
    }
}

/// Small rounded icon tile used in settings rows and hub cards.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.onTint)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
            .accessibilityHidden(true)
    }
}
