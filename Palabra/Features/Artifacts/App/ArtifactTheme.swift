import SwiftUI
import UIKit

/// The app's colors as CSS custom properties for app artifacts (`palabra.theme`, `var(--ink)`).
enum ArtifactTheme {
    static func variables(for scheme: ColorScheme) -> [String: String] {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        func hex(_ color: Color) -> String {
            let resolved = UIColor(color).resolvedColor(with: traits)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }
        return [
            "ink": hex(Theme.ink),
            "ink-secondary": hex(Theme.inkSecondary),
            "surface": hex(Theme.surface),
            "accent": hex(Theme.accent),
            "error": hex(Theme.error),
            "background": hex(Theme.backgroundTop),
        ]
    }
}
