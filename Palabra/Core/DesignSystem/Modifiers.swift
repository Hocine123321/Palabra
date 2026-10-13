import SwiftUI

extension View {
    /// The ground behind a `Form` or `List` screen: warm neutral with muted cutouts that the
    /// glass rows bend. Replaces the system grey grouped background. Pair it with
    /// `themedSection()` on each `Section`.
    func glassScreen(_ style: ScreenBackdrop.Style = .calm) -> some View {
        scrollContentBackground(.hidden)
            .background { ScreenBackdrop(style: style) }
    }

    /// Row surface for a `Section` inside a `glassScreen()` list: a thin material over the cutouts.
    func themedSection() -> some View {
        listRowBackground(ListRowGlass())
    }

    /// The standard card background (`GlassSurface`) for views that lay out their own padding.
    func glassCard(cornerRadius: CGFloat = Theme.Radius.card, tint: Color? = nil) -> some View {
        background { GlassBackground(cornerRadius: cornerRadius, tint: tint) }
    }

    /// Capsule glass for chips, pills and compact controls.
    func glassCapsule(tint: Color? = nil) -> some View {
        background { GlassBackground(cornerRadius: Theme.Radius.pill, tint: tint) }
    }

    /// A bottom accessory: a floating glass capsule above the tab bar (add-word bar,
    /// "ask about this word", "ask for a change").
    func glassAccessory() -> some View {
        padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .glassCapsule()
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
    }

    /// A sunken fill for things that sit inside glass (inputs, tracks, inner chips).
    func innerFill(cornerRadius: CGFloat = Theme.Radius.medium) -> some View {
        background(Theme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ListRowGlass: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.surface.opacity(0.55)
        }
    }
}

/// The full-width call-to-action button used for a screen's main action: a Claude Orange capsule.
/// Compact inline actions keep the system `.bordered` / `.borderedProminent` styles.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonLabel(configuration: configuration)
    }

    private struct PrimaryButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.onTint) // ink on orange: 5.4:1 (white is 3.1:1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md - 2)
                .background {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [Theme.accent.opacity(isEnabled ? 0.92 : 0.4), Theme.accent.opacity(isEnabled ? 1 : 0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                        }
                        .shadow(color: Theme.accent.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 6)
                }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(Motion.reduced(Motion.quick), value: configuration.isPressed)
        }
    }
}

/// A secondary full-width or inline action on glass: ink text, capsule glass.
struct GlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .glassCapsule()
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.reduced(Motion.quick), value: configuration.isPressed)
    }
}

/// A round 44pt glass icon button (toolbar-style controls inside content).
struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 44, height: 44)
            .glassCapsule()
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.reduced(Motion.quick), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == GlassActionButtonStyle {
    static var glassAction: GlassActionButtonStyle { GlassActionButtonStyle() }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { GlassIconButtonStyle() }
}
