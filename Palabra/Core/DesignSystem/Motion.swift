import SwiftUI
import UIKit

/// Springs under 0.35s. Every animation in the app goes through `animate` / `reduced`
/// so the system Reduce Motion setting is honored everywhere.
enum Motion {
    static let quick = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.82)

    static func respecting(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// `withAnimation`, skipped when Reduce Motion is on.
    @MainActor
    static func animate<Result>(_ animation: Animation = standard, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(reduced(animation), body)
    }

    /// For `.animation(_:value:)`: `nil` when Reduce Motion is on.
    @MainActor
    static func reduced(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}
