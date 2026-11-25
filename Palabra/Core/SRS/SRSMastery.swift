import Foundation

/// How well a card is known, as 0...1, for progress rings. Pure.
enum SRSMastery {
    /// A review interval of this many days counts as fully learned.
    static let matureDays = 21.0

    static func fraction(for state: SRSState) -> Double {
        switch state.phase {
        case .new: return 0
        case .learning: return 0.12
        case .review: return min(1, max(0.2, state.interval / matureDays))
        }
    }
}
