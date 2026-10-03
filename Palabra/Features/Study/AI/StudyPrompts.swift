import Foundation

enum StudyPrompts {
    /// Gemini `responseSchema` for the notes -> deck call.
    static let deckSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["title", "cards"],
        "properties": [
            "title": ["type": "STRING"],
            "cards": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "propertyOrdering": ["front", "back"],
                    "properties": [
                        "front": ["type": "STRING"],
                        "back": ["type": "STRING"]
                    ],
                    "required": ["front", "back"]
                ]
            ]
        ],
        "required": ["title", "cards"]
    ]

    static func cardSystemInstruction(maxCards: Int, maxFieldLength: Int, maxTitleLength: Int) -> String {
        """
        You turn study notes into flashcards. Respond with JSON only, matching the schema.
        - "title": a short name for the deck, at most \(maxTitleLength) characters.
        - "cards": at most \(maxCards) cards. Each card tests exactly one fact. "front" is a short question or term; "back" is the concise answer. Keep each field under \(maxFieldLength) characters.
        - Use only information that is in the notes. Do not invent facts. Skip duplicates.
        - Write the cards in the same language as the notes. Do not translate.
        The user message contains the notes.
        """
    }
}
