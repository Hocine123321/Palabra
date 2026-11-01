import Foundation

/// The small helpers `book3d.js` and `app.js` share (`clamp`, `lerp`, `smooth`), so ported code reads the same.
enum BookMath {
    static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, x)) }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Hermite smoothstep between `a` and `b`.
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }
}
