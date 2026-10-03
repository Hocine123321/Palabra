import SwiftUI

extension View {
    /// The cream gradient behind a `Form` or `List` screen, replacing the system
    /// grey grouped background, so settings-style screens match the rest of the app.
    /// Pair it with `themedSection()` on each `Section` for matching row surfaces.
    func creamScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Row surface for a `Section` inside a `creamScreen()` list.
    func themedSection() -> some View {
        listRowBackground(Theme.surface)
    }

    /// The standard card background (`GlassSurface`) for views that lay out their own padding.
    func glassCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background { GlassSurface(cornerRadius: cornerRadius) { Color.clear } }
    }
}

/// The full-width call-to-action button used for a screen's main action.
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
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md - 4)
                .background(
                    Theme.accent.opacity(isEnabled ? 1 : 0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
