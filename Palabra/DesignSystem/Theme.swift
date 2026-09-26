import SwiftUI

/// The cream / warm off-white palette, type, spacing and radii used
/// throughout the app. Light appearance only.
enum Theme {
    static let backgroundTop = Color(hex: 0xFBF7EE)
    static let backgroundBottom = Color(hex: 0xF3EBDC)
    static let surface = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x2A2520)
    static let inkSecondary = Color(hex: 0x6B6258)
    static let accent = Color(hex: 0xB8694A)
    static let error = Color(hex: 0xA8483D)

    static let tileTints: [Color] = [
        accent,
        Color(hex: 0x8FA58C), // sage
        Color(hex: 0xE7D9BF), // sand
        Color(hex: 0x8FA3B5), // dusty blue
        Color(hex: 0xE8B48B), // apricot
        Color(hex: 0xA9A58A)  // olive-gray
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
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
