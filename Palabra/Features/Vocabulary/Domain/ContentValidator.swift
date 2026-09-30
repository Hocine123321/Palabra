import Foundation

/// Validates and trims a raw AI-decoded `WordContent` before anything is saved.
/// Nothing reaches the Library unless every rule here passes.
enum ContentValidator {
    /// Upper bounds for the "Word Forms" section. Some words (verbs especially)
    /// make the model return enormous conjugation tables; these keep what is
    /// stored and rendered to a sane size.
    static let maxFormGroups = 12
    static let maxFormsPerGroup = 12
    static let maxFormLength = 60
    static let maxNoteLength = 90

    private static func clip(_ s: String, to limit: Int) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)) + "…"
    }

    static func validate(_ raw: WordContent) -> Result<WordContent, AIError> {
        var failed: [String] = []

        let word = raw.word.trimmed
        if word.isEmpty || word.count > 60 { failed.append("word") }

        let examples = raw.examples.map {
            WordContent.Example(context: $0.context.trimmed, spanish: $0.spanish.trimmed, english: $0.english.trimmed)
        }
        if examples.count != 3 {
            failed.append("examples.count")
        } else {
            if examples.contains(where: { $0.context.isEmpty || $0.spanish.isEmpty || $0.english.isEmpty }) {
                failed.append("examples.fields")
            }
            if Set(examples.map(\.spanish)).count != examples.count {
                failed.append("examples.distinct")
            }
        }

        let translations = raw.meaning.translations.map(\.trimmed).filter { !$0.isEmpty }
        let meaningExplanation = raw.meaning.explanation.trimmed
        if translations.isEmpty { failed.append("meaning.translations") }
        if meaningExplanation.isEmpty { failed.append("meaning.explanation") }

        let usageExplanation = raw.usage.explanation.trimmed
        let register = raw.usage.register.trimmed
        if usageExplanation.isEmpty { failed.append("usage.explanation") }
        if register.isEmpty { failed.append("usage.register") }
        let nuance = raw.usage.nuance?.trimmed
        let cleanNuance = (nuance?.isEmpty ?? true) ? nil : nuance

        let partOfSpeech = raw.forms.partOfSpeech.trimmed
        if partOfSpeech.isEmpty { failed.append("forms.partOfSpeech") }

        var groups: [WordContent.Forms.FormGroup] = []
        for group in raw.forms.groups.prefix(maxFormGroups) {
            let label = group.label.trimmed
            let items = group.items
                .map { WordContent.Forms.FormGroup.FormItem(form: clip($0.form.trimmed, to: maxFormLength), note: nonEmpty($0.note).map { clip($0, to: maxNoteLength) }) }
                .filter { !$0.form.isEmpty }
                .prefix(maxFormsPerGroup)
            if !label.isEmpty, !items.isEmpty {
                groups.append(.init(label: clip(label, to: maxFormLength), items: Array(items)))
            }
        }
        if groups.isEmpty { failed.append("forms.groups") }

        var similar = raw.similarWords
            .map { WordContent.SimilarWord(word: $0.word.trimmed, difference: $0.difference.trimmed) }
            .filter { !$0.word.isEmpty && !$0.difference.isEmpty }
        if similar.isEmpty { failed.append("similarWords") }
        if similar.count > 8 { similar = Array(similar.prefix(8)) }

        guard failed.isEmpty else { return .failure(.validationFailed(failed)) }

        return .success(WordContent(
            word: word,
            examples: examples,
            meaning: .init(translations: translations, explanation: meaningExplanation),
            usage: .init(explanation: usageExplanation, register: register, nuance: cleanNuance),
            forms: .init(partOfSpeech: partOfSpeech, groups: groups),
            similarWords: similar
        ))
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmed, !t.isEmpty else { return nil }
        return t
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
