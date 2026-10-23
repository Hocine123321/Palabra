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
    /// Upper bounds for the rest of the displayed text, so one runaway reply cannot stretch a screen or bloat the store.
    /// Generous on purpose: normal replies are far below them and are never altered.
    static let maxContextLength = 300
    static let maxParagraphLength = 1_500
    static let maxTranslations = 10
    static let maxTranslationLength = 120
    static let maxRegisterLength = 120
    static let maxPartOfSpeechLength = 60
    static let maxSimilarWordLength = 60
    static let maxDifferenceLength = 500
    /// The model is asked for exactly three; this only stops a damaged import from carrying a long list.
    static let maxExamples = 12

    private static func clip(_ s: String, to limit: Int) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)) + "…"
    }

    static func validate(_ raw: WordContent) -> Result<WordContent, AIError> {
        let (content, failed) = clean(raw)
        return failed.isEmpty ? .success(content) : .failure(.validationFailed(failed))
    }

    /// The same trimming and clipping as `validate`, but nothing is rejected: used for imported libraries, so an old or
    /// slightly odd export still comes in while a damaged one cannot bring huge strings or lists with it.
    static func clipped(_ raw: WordContent) -> WordContent { clean(raw).content }

    private static func clean(_ raw: WordContent) -> (content: WordContent, failed: [String]) {
        var failed: [String] = []

        let word = raw.word.trimmed
        if word.isEmpty || word.count > 60 { failed.append("word") }

        let examples = raw.examples.prefix(maxExamples).map {
            WordContent.Example(
                context: clip($0.context.trimmed, to: maxContextLength),
                spanish: clip($0.spanish.trimmed, to: maxParagraphLength),
                english: clip($0.english.trimmed, to: maxParagraphLength)
            )
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

        let translations = Array(raw.meaning.translations.map { clip($0.trimmed, to: maxTranslationLength) }.filter { !$0.isEmpty }.prefix(maxTranslations))
        let meaningExplanation = clip(raw.meaning.explanation.trimmed, to: maxParagraphLength)
        if translations.isEmpty { failed.append("meaning.translations") }
        if meaningExplanation.isEmpty { failed.append("meaning.explanation") }

        let usageExplanation = clip(raw.usage.explanation.trimmed, to: maxParagraphLength)
        let register = clip(raw.usage.register.trimmed, to: maxRegisterLength)
        if usageExplanation.isEmpty { failed.append("usage.explanation") }
        if register.isEmpty { failed.append("usage.register") }
        let nuance = raw.usage.nuance.map { clip($0.trimmed, to: maxParagraphLength) }
        let cleanNuance = (nuance?.isEmpty ?? true) ? nil : nuance

        let partOfSpeech = clip(raw.forms.partOfSpeech.trimmed, to: maxPartOfSpeechLength)
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
            .map { WordContent.SimilarWord(word: clip($0.word.trimmed, to: maxSimilarWordLength), difference: clip($0.difference.trimmed, to: maxDifferenceLength)) }
            .filter { !$0.word.isEmpty && !$0.difference.isEmpty }
        if similar.isEmpty { failed.append("similarWords") }
        if similar.count > 8 { similar = Array(similar.prefix(8)) }

        let content = WordContent(
            word: word,
            examples: examples,
            meaning: .init(translations: translations, explanation: meaningExplanation),
            usage: .init(explanation: usageExplanation, register: register, nuance: cleanNuance),
            forms: .init(partOfSpeech: partOfSpeech, groups: groups),
            similarWords: similar,
            contentLanguage: raw.contentLanguage
        )
        return (content, failed)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmed, !t.isEmpty else { return nil }
        return t
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
