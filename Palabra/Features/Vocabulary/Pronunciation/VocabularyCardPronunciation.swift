import SwiftUI

/// Pronunciation control for a Study card that was mirrored from a library word.
/// Lives in Vocabulary so the Study feature never needs to know about `Word`.
struct VocabularyCardPronunciation: View {
    let wordID: UUID
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let word = environment.repository.allWords().first(where: { $0.id == wordID }) {
            PronunciationButton(word: word)
        }
    }
}
