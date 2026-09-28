import SwiftUI

/// Springs under 0.35s, with a Reduce Motion escape hatch every call site uses.
enum Motion {
    static let quick = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.82)

    static func respecting(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
