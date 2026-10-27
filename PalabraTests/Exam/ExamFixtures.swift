import Foundation
@testable import Palabra

/// A small Spanish library as the exam sees it.
enum ExamFixtures {
    static func word(
        _ headword: String, _ translations: [String], pos: String = "verb",
        examples: [(String, String)] = [], forms: [(String, String, String?)] = [], similar: [(String, String)] = [],
        category: String? = nil, tags: [String] = [], needsReview: Bool = false, created: Int = 0
    ) -> ExamWord {
        ExamWord(
            id: UUID(), headword: headword, translations: translations, partOfSpeech: pos,
            examples: examples.map { ExamWord.Example(spanish: $0.0, english: $0.1) },
            forms: forms.map { ExamWord.Form(label: $0.0, form: $0.1, note: $0.2) },
            similar: similar.map { ExamWord.Similar(word: $0.0, difference: $0.1) },
            category: category, tags: tags, createdAt: Date(timeIntervalSince1970: TimeInterval(created)), needsReview: needsReview
        )
    }

    /// Eight verbs, each with an example sentence that uses a form of the verb, and three forms.
    static func library() -> [ExamWord] {
        [
            word("hablar", ["to speak", "to talk"], examples: [("Hablo español con mis amigos.", "I speak Spanish with my friends.")],
                 forms: [("Present", "hablo", "yo"), ("Present", "hablas", "tú"), ("Present", "habla", "él")],
                 similar: [("decir", "decir is to say something specific")], category: "Verbs", tags: ["common"], created: 1),
            word("comer", ["to eat"], examples: [("Como pan todos los días.", "I eat bread every day.")],
                 forms: [("Present", "como", "yo"), ("Present", "comes", "tú"), ("Present", "come", "él")],
                 category: "Food", tags: ["common"], needsReview: true, created: 2),
            word("beber", ["to drink"], examples: [("Bebo agua por la mañana.", "I drink water in the morning.")],
                 forms: [("Present", "bebo", "yo"), ("Present", "bebes", "tú"), ("Present", "bebe", "él")],
                 category: "Food", created: 3),
            word("vivir", ["to live"], examples: [("Vivo en una ciudad pequeña.", "I live in a small city.")],
                 forms: [("Present", "vivo", "yo"), ("Present", "vives", "tú"), ("Present", "vive", "él")],
                 category: "Verbs", needsReview: true, created: 4),
            word("correr", ["to run"], examples: [("Corro por el parque cada tarde.", "I run in the park every afternoon.")],
                 forms: [("Present", "corro", "yo"), ("Present", "corres", "tú"), ("Present", "corre", "él")], created: 5),
            word("escribir", ["to write"], examples: [("Escribo una carta a mi madre.", "I write a letter to my mother.")],
                 forms: [("Present", "escribo", "yo"), ("Present", "escribes", "tú"), ("Present", "escribe", "él")], created: 6),
            word("leer", ["to read"], examples: [("Leo un libro antes de dormir.", "I read a book before sleeping.")],
                 forms: [("Present", "leo", "yo"), ("Present", "lees", "tú"), ("Present", "lee", "él")], created: 7),
            word("abrir", ["to open"], examples: [("Abro la puerta de la casa.", "I open the door of the house.")],
                 forms: [("Present", "abro", "yo"), ("Present", "abres", "tú"), ("Present", "abre", "él")], created: 8),
        ]
    }

    /// Every skill that needs neither speech nor AI.
    static let offlineSkills: Set<ExamSkill> = [.vocabulary, .typing, .grammar, .listening]
}
