import Foundation

/// The structured result the AI returns for one Spanish word, and what the app stores.
struct WordContent: Codable, Equatable, Sendable {
    var word: String
    var examples: [Example]
    var meaning: Meaning
    var usage: Usage
    var forms: Forms
    var similarWords: [SimilarWord]
    /// The language used for learner-facing explanations when this content was generated.
    var contentLanguage: SupportedLanguage

    init(
        word: String,
        examples: [Example],
        meaning: Meaning,
        usage: Usage,
        forms: Forms,
        similarWords: [SimilarWord],
        contentLanguage: SupportedLanguage = .english
    ) {
        self.word = word
        self.examples = examples
        self.meaning = meaning
        self.usage = usage
        self.forms = forms
        self.similarWords = similarWords
        self.contentLanguage = contentLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case word, examples, meaning, usage, forms, similarWords, contentLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        examples = try container.decode([Example].self, forKey: .examples)
        meaning = try container.decode(Meaning.self, forKey: .meaning)
        usage = try container.decode(Usage.self, forKey: .usage)
        forms = try container.decode(Forms.self, forKey: .forms)
        similarWords = try container.decode([SimilarWord].self, forKey: .similarWords)
        contentLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .contentLanguage) ?? .english
    }

    struct Example: Codable, Equatable, Sendable {
        var context: String
        var spanish: String
        var translation: String

        init(context: String, spanish: String, translation: String) {
            self.context = context
            self.spanish = spanish
            self.translation = translation
        }

        /// Source compatibility for older callers and stored English content.
        init(context: String, spanish: String, english: String) {
            self.init(context: context, spanish: spanish, translation: english)
        }

        var english: String {
            get { translation }
            set { translation = newValue }
        }

        private enum CodingKeys: String, CodingKey {
            case context, spanish, translation, english
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            context = try container.decode(String.self, forKey: .context)
            spanish = try container.decode(String.self, forKey: .spanish)
            translation = try container.decodeIfPresent(String.self, forKey: .translation)
                ?? container.decode(String.self, forKey: .english)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(context, forKey: .context)
            try container.encode(spanish, forKey: .spanish)
            try container.encode(translation, forKey: .translation)
        }
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
    static let empty = WordContent(
        word: "",
        examples: [],
        meaning: Meaning(translations: [], explanation: ""),
        usage: Usage(explanation: "", register: "", nuance: nil),
        forms: Forms(partOfSpeech: "", groups: []),
        similarWords: [],
        contentLanguage: .english
    )
}
