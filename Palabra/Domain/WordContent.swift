import Foundation

/// The structured result the AI returns for one Spanish word, and what the app stores for it.
struct WordContent: Codable, Equatable, Sendable {
    var word: String
    var examples: [Example]
    var meaning: Meaning
    var usage: Usage
    var forms: Forms
    var similarWords: [SimilarWord]

    struct Example: Codable, Equatable, Sendable {
        var context: String
        var spanish: String
        var english: String
    }

    struct Meaning: Codable, Equatable, Sendable {
        var translations: [String]
        var explanation: String
    }

    struct Usage: Codable, Equatable, Sendable {
        var explanation: String
        var register: String
        var nuance: String?
    }

    struct Forms: Codable, Equatable, Sendable {
        var partOfSpeech: String
        var groups: [FormGroup]

        struct FormGroup: Codable, Equatable, Sendable {
            var label: String
            var items: [FormItem]

            struct FormItem: Codable, Equatable, Sendable {
                var form: String
                var note: String?
            }
        }
    }

    struct SimilarWord: Codable, Equatable, Sendable {
        var word: String
        var difference: String
    }

    /// Fallback used when stored content fails to decode (corrupt row, older schema).
    /// The UI must render this without crashing; it never passes `ContentValidator`.
    static let empty = WordContent(
        word: "",
        examples: [],
        meaning: Meaning(translations: [], explanation: ""),
        usage: Usage(explanation: "", register: "", nuance: nil),
        forms: Forms(partOfSpeech: "", groups: []),
        similarWords: []
    )
}
