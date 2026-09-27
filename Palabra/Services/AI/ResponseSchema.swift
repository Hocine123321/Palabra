import Foundation

/// The Gemini `responseSchema` (OpenAPI subset) for `WordContent`, and the
/// request bodies built from it.
enum ResponseSchema {
    static let wordContentSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["word", "examples", "meaning", "usage", "forms", "similarWords"],
        "properties": [
            "word": ["type": "STRING"],
            "examples": [
                "type": "ARRAY", "minItems": 3, "maxItems": 3,
                "items": [
                    "type": "OBJECT",
                    "propertyOrdering": ["context", "spanish", "translation"],
                    "properties": [
                        "context": ["type": "STRING"],
                        "spanish": ["type": "STRING"],
                        "translation": ["type": "STRING"]
                    ],
                    "required": ["context", "spanish", "translation"]
                ]
            ],
            "meaning": [
                "type": "OBJECT",
                "propertyOrdering": ["translations", "explanation"],
                "properties": [
                    "translations": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "explanation": ["type": "STRING"]
                ],
                "required": ["translations", "explanation"]
            ],
            "usage": [
                "type": "OBJECT",
                "propertyOrdering": ["explanation", "register", "nuance"],
                "properties": [
                    "explanation": ["type": "STRING"],
                    "register": ["type": "STRING"],
                    "nuance": ["type": "STRING", "nullable": true]
                ],
                "required": ["explanation", "register"]
            ],
            "forms": [
                "type": "OBJECT",
                "propertyOrdering": ["partOfSpeech", "groups"],
                "properties": [
                    "partOfSpeech": ["type": "STRING"],
                    "groups": [
                        "type": "ARRAY",
                        "items": [
                            "type": "OBJECT",
                            "propertyOrdering": ["label", "items"],
                            "properties": [
                                "label": ["type": "STRING"],
                                "items": [
                                    "type": "ARRAY",
                                    "items": [
                                        "type": "OBJECT",
                                        "propertyOrdering": ["form", "note"],
                                        "properties": [
                                            "form": ["type": "STRING"],
                                            "note": ["type": "STRING", "nullable": true]
                                        ],
                                        "required": ["form"]
                                    ]
                                ]
                            ],
                            "required": ["label", "items"]
                        ]
                    ]
                ],
                "required": ["partOfSpeech", "groups"]
            ],
            "similarWords": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "propertyOrdering": ["word", "difference"],
                    "properties": [
                        "word": ["type": "STRING"],
                        "difference": ["type": "STRING"]
                    ],
                    "required": ["word", "difference"]
                ]
            ]
        ],
        "required": ["word", "examples", "meaning", "usage", "forms", "similarWords"]
    ]

    static func wordRequestBody(word: String, systemInstruction: String, maxOutputTokens: Int, useSchema: Bool) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "temperature": 0.7,
            "maxOutputTokens": maxOutputTokens
        ]
        if useSchema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = wordContentSchema
        }
        return [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": word]]]],
            "generationConfig": generationConfig
        ]
    }

    // MARK: - Study planner (flashcards / quiz)

    static let flashcardArraySchema: [String: Any] = [
        "type": "ARRAY",
        "minItems": 1,
        "items": [
            "type": "OBJECT",
            "propertyOrdering": ["front", "back", "hint"],
            "properties": [
                "front": ["type": "STRING"],
                "back": ["type": "STRING"],
                "hint": ["type": "STRING", "nullable": true]
            ],
            "required": ["front", "back"]
        ]
    ]

    static let quizArraySchema: [String: Any] = [
        "type": "ARRAY",
        "minItems": 1,
        "items": [
            "type": "OBJECT",
            "propertyOrdering": ["question", "options", "correctIndex", "explanation"],
            "properties": [
                "question": ["type": "STRING"],
                "options": ["type": "ARRAY", "minItems": 4, "maxItems": 4, "items": ["type": "STRING"]],
                "correctIndex": ["type": "INTEGER"],
                "explanation": ["type": "STRING", "nullable": true]
            ],
            "required": ["question", "options", "correctIndex"]
        ]
    ]

    static func notesRequestBody(notes: String, systemInstruction: String, schema: [String: Any], maxOutputTokens: Int, useSchema: Bool) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "temperature": 0.5,
            "maxOutputTokens": maxOutputTokens
        ]
        if useSchema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = schema
        }
        return [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": notes]]]],
            "generationConfig": generationConfig
        ]
    }
}
