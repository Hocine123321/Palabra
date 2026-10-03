import Foundation

struct GeneratedDeck: Equatable {
    var title: String
    var cards: [CardDraft]
}

enum CardGeneratorLimits {
    static let maxNotesLength = 12_000
    static let minNotesLength = 20
    static let maxCards = 40
    static let maxFieldLength = 300
    static let maxTitleLength = 60
}

/// Turns pasted notes into card drafts via the generic `generateJSON` call.
/// Nothing is saved here; the caller previews and confirms.
struct CardGenerator {
    let ai: AIClient

    private struct Payload: Decodable {
        struct Item: Decodable {
            let front: String
            let back: String
        }
        let title: String
        let cards: [Item]
    }

    func generate(notes: String, apiKey: String, model: AIModel) async -> Result<GeneratedDeck, AIError> {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CardGeneratorLimits.minNotesLength else {
            return .failure(.validationFailed(["Notes are too short."]))
        }
        let prompt = String(trimmed.prefix(CardGeneratorLimits.maxNotesLength))
        let result = await ai.generateJSON(
            prompt: prompt,
            systemInstruction: StudyPrompts.cardSystemInstruction(
                maxCards: CardGeneratorLimits.maxCards,
                maxFieldLength: CardGeneratorLimits.maxFieldLength,
                maxTitleLength: CardGeneratorLimits.maxTitleLength
            ),
            schema: StudyPrompts.deckSchema,
            apiKey: apiKey,
            model: model,
            temperature: 0.3
        )
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let text):
            return Self.parse(text)
        }
    }

    /// Decodes and validates: trims, drops empty cards, caps lengths and count, removes duplicate fronts.
    static func parse(_ text: String) -> Result<GeneratedDeck, AIError> {
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.malformedResponse)
        }
        var seen = Set<String>()
        var cards: [CardDraft] = []
        for item in payload.cards {
            let front = cap(item.front, CardGeneratorLimits.maxFieldLength)
            let back = cap(item.back, CardGeneratorLimits.maxFieldLength)
            guard !front.isEmpty, !back.isEmpty else { continue }
            guard seen.insert(front.lowercased()).inserted else { continue }
            cards.append(CardDraft(front: front, back: back))
            if cards.count == CardGeneratorLimits.maxCards { break }
        }
        guard !cards.isEmpty else { return .failure(.malformedResponse) }
        return .success(GeneratedDeck(title: cap(payload.title, CardGeneratorLimits.maxTitleLength), cards: cards))
    }

    private static func cap(_ value: String, _ limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
