import Foundation

/// Small library shortcuts that touch both vocabulary and Need Review. The App layer is the one place
/// that knows both, so `Features/Vocabulary` never imports `Features/Review`.
extension AppEnvironment {
    /// Puts one word on the Need Review page. Score 1: the person flagged it themselves.
    /// Returns whether a flag was written.
    @discardableResult
    func flagForReview(_ word: Word) -> Bool {
        let flag = ReviewFlag(
            wordID: word.id,
            headword: word.spanish,
            translation: word.translation,
            score: 1,
            note: "",
            sourceArtifactID: nil
        )
        return review.flag([flag], now: Date()) > 0
    }
}
