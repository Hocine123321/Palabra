import SwiftUI
import UIKit

/// "Recortes & Glass": a quiet warm-neutral ground, muted paper cutouts behind
/// Liquid Glass controls, and Claude Orange as the one accent. Colours, type,
/// spacing and radii adapt to light and dark appearance.
enum Theme {
    // MARK: Ground and ink

    static let backgroundTop = Color(lightHex: 0xF5F3EE, darkHex: 0x1B1A18)
    static let backgroundBottom = Color(lightHex: 0xECE9E1, darkHex: 0x121110)
    /// Solid surface for small things (text editors, popovers) and list rows.
    static let surface = Color(lightHex: 0xFCFBF8, darkHex: 0x262522)
    static let ink = Color(lightHex: 0x1F1D1A, darkHex: 0xF1EFE8)
    static let inkSecondary = Color(lightHex: 0x67645C, darkHex: 0xB4B1A7)
    /// Fill for things that sit *inside* glass (inputs, inner chips, tracks). Glass never nests glass.
    static let fill = Color(lightHex: 0xE7E4DB, darkHex: 0x34322E)

    // MARK: Accent

    /// Claude Orange. Fills, tint, selection.
    static let accent = Color(hex: 0xD97757)
    /// Pressed state and orange *text* on light ground (the plain accent is too light for small text).
    static let accentDeep = Color(lightHex: 0xA9502F, darkHex: 0xE89574)
    static let accentSoft = Color(lightHex: 0xF4DDD2, darkHex: 0x4A3228)
    static let error = Color(lightHex: 0xA8483D, darkHex: 0xF08A80)
    static let success = Color(lightHex: 0x5E7A4A, darkHex: 0x9DBB86)

    /// Text on a cutout tint. Tints are light enough in both appearances for dark ink.
    static let onTint = Color(hex: 0x1F1D1A)

    /// Warm paper that stays light in dark mode, for content drawn for a light page (Wolfram's images).
    static let paper = Color(hex: 0xFCFBF8)

    /// Muted cutout palette: Claude Orange first, then sage, sky, sand, apricot, stone.
    static let tileTints: [Color] = [
        accent,
        Color(hex: 0xA3B18A), // sage
        Color(hex: 0x9DBAD5), // sky
        Color(hex: 0xE3D5B8), // sand
        Color(hex: 0xEBB491), // apricot
        Color(hex: 0xC6C3B6)  // stone
    ]

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Deterministic tile tint for a word's identity key.
    static func tint(for key: String) -> Color {
        tileTints[WordKey.tintIndex(key, count: tileTints.count)]
    }

    // MARK: Type

    enum Font {
        /// Display face: SF Rounded, bold. Headwords, titles, numbers.
        static func face(size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        /// Kept for call sites that pick a size; same face as the roles below.
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        /// Use these roles instead of ad-hoc sizes so the same kind of heading looks
        /// the same on every screen.
        /// Hero word / flashcard face.
        static let display = face(size: 40, weight: .bold)
        /// Onboarding and sheet headings.
        static let title = face(size: 26, weight: .bold)
        /// Card titles, section titles, empty-state titles.
        static let heading = face(size: 20, weight: .bold)
        /// A row's main text in lists.
        static let rowTitle = face(size: 18, weight: .semibold)
        /// Text inside a cutout tile.
        static let tile = face(size: 16, weight: .bold)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// Concentric: an inner radius is its container's radius minus the inset between them.
    enum Radius {
        /// Skeleton blocks, small inline shapes.
        static let small: CGFloat = 10
        /// Inner controls: text fields, inner cards, bubbles, list rows.
        static let medium: CGFloat = 20
        /// Cards and surfaces.
        static let card: CGFloat = 28
        /// Sheets and hero cutouts.
        static let sheet: CGFloat = 40
        /// Capsules: chips, buttons, bars. Larger than any control height.
        static let pill: CGFloat = 100
    }

    /// The two textbooks (Books tab). Each is a page of its own: History is warm archive paper with oxblood ink accents and a
    /// serif face; Geography is a cool atlas sheet with a teal accent. Both stay readable in light and dark appearance.
    enum Textbook {
        struct Palette {
            let paper: Color
            let paperEdge: Color
            let ink: Color
            let inkSecondary: Color
            /// Titles, markers, links and highlights. At least 4.5:1 on `paper` in both appearances.
            let accent: Color
            /// Hairlines and borders.
            let rule: Color
            let design: SwiftUI.Font.Design

            func font(_ style: SwiftUI.Font.TextStyle, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
                .system(style, design: design).weight(weight)
            }
        }

        static let history = Palette(
            paper: Color(lightHex: 0xF4EBD9, darkHex: 0x2A2520),
            paperEdge: Color(lightHex: 0xE6D8BC, darkHex: 0x3A322A),
            ink: Color(lightHex: 0x2B2218, darkHex: 0xEFE6D4),
            inkSecondary: Color(lightHex: 0x6B5B45, darkHex: 0xB9AA92),
            accent: Color(lightHex: 0x8B2E22, darkHex: 0xE08A78),
            rule: Color(lightHex: 0xC9B88F, darkHex: 0x5A4E3C),
            design: .serif
        )

        static let geography = Palette(
            paper: Color(lightHex: 0xEEF3F0, darkHex: 0x1E2624),
            paperEdge: Color(lightHex: 0xD5E2DC, darkHex: 0x2E3A37),
            ink: Color(lightHex: 0x1B2926, darkHex: 0xE6EFEC),
            inkSecondary: Color(lightHex: 0x4F6560, darkHex: 0xA9BDB7),
            accent: Color(lightHex: 0x1F6F78, darkHex: 0x6CC1C9),
            rule: Color(lightHex: 0xB5CBC3, darkHex: 0x40504C),
            design: .default
        )
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
