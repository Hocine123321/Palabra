import SwiftUI
import UIKit

/// The cream / warm off-white palette, type, spacing and radii used
/// throughout the app, adapting to light and dark appearance.
enum Theme {
    static let backgroundTop = Color(lightHex: 0xFBF7EE, darkHex: 0x1D1916)
    static let backgroundBottom = Color(lightHex: 0xF3EBDC, darkHex: 0x120F0D)
    static let surface = Color(lightHex: 0xFFFDF8, darkHex: 0x29231F)
    static let ink = Color(lightHex: 0x2A2520, darkHex: 0xF6EFE5)
    static let inkSecondary = Color(lightHex: 0x6B6258, darkHex: 0xB8AA9C)
    static let accent = Color(lightHex: 0xB8694A, darkHex: 0xD88961)
    static let error = Color(lightHex: 0xA8483D, darkHex: 0xF08A80)

    static let tileTints: [Color] = [
        accent,
        Color(lightHex: 0x8FA58C, darkHex: 0x789A80), // sage
        Color(lightHex: 0xE7D9BF, darkHex: 0xB69D76), // sand
        Color(lightHex: 0x8FA3B5, darkHex: 0x7792AD), // dusty blue
        Color(lightHex: 0xE8B48B, darkHex: 0xD49069), // apricot
        Color(lightHex: 0xA9A58A, darkHex: 0x9E9B77)  // olive-gray
    ]

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Deterministic tile tint for a word's identity key.
    static func tint(for key: String) -> Color {
        tileTints[WordKey.tintIndex(key, count: tileTints.count)]
    }

    enum Font {
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .serif)
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 100
    }
}

extension Color {
    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension SettingsStore.AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
