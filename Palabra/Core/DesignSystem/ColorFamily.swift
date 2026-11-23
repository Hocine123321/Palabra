import Foundation

/// A named colour a piece of content can ask the design system to paint with (for example a word
/// that is itself a colour). Pure names: the actual muted tints live in `Theme.tint(for:shade:)`.
enum ColorFamily: CaseIterable {
    case red, orange, yellow, lime, green, teal
    case lightBlue, blue, navy
    case purple, lavender, pink, maroon
    case brown, beige
    case gray, black, white
    case gold, silver
}

/// Lighter or deeper variant of a `ColorFamily` ("azul claro", "verde oscuro").
enum ColorShade {
    case light, normal, deep
}
