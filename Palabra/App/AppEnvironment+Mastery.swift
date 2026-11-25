import Foundation

/// Where Study and Vocabulary meet for progress rings: the App layer reads the mirrored Vocabulary deck and hands
/// the library plain numbers, so neither feature imports the other.
extension AppEnvironment {
    /// How far along each library word's flashcard is (0...1). Words without a started card are absent.
    func wordMastery() -> [UUID: Double] {
        guard let deck = cards.decks().first(where: { $0.kind == .vocabulary }) else { return [:] }
        var result: [UUID: Double] = [:]
        for card in cards.cards(inDeck: deck.id) {
            guard let id = card.sourceWordID else { continue }
            let fraction = SRSMastery.fraction(for: card.srs)
            if fraction > 0 { result[id] = fraction }
        }
        return result
    }
}
