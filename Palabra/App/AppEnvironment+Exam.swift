import Foundation

/// The exam's link to the rest of the app. Study never imports `Word`: this is where words become `ExamWord`s.
extension AppEnvironment {
    /// Every library word as the exam sees it, with the Need Review flag.
    func examWords() -> [ExamWord] {
        let flagged = Set(review.openNeeds().map(\.wordID))
        return repository.allWords().compactMap { word in
            let content = word.content
            let headword = word.spanish.trimmingCharacters(in: .whitespacesAndNewlines)
            var translations = content.meaning.translations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let main = word.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if translations.isEmpty, !main.isEmpty { translations = [main] }
            guard !headword.isEmpty, !translations.isEmpty else { return nil }
            return ExamWord(
                id: word.id,
                headword: headword,
                translations: translations,
                partOfSpeech: word.partOfSpeech,
                examples: content.examples.map { ExamWord.Example(spanish: $0.spanish, english: $0.translation) },
                forms: content.forms.groups.flatMap { group in
                    group.items.map { ExamWord.Form(label: group.label, form: $0.form, note: $0.note) }
                },
                similar: content.similarWords.map { ExamWord.Similar(word: $0.word, difference: $0.difference) },
                category: word.category,
                tags: word.tags,
                createdAt: word.createdAt,
                needsReview: flagged.contains(word.id)
            )
        }
    }

    /// The AI side of an exam, or nil without a key and model (an exam then runs on the person's words alone).
    func examAI() -> ExamAI? {
        guard hasAPIKey, selectedModel != nil else { return nil }
        return ExamAI(generate: { [weak self] prompt, system, schema, temperature in
            guard let self else { return .failure(.unknown(nil, "The app was closed.")) }
            return await self.examGenerate(prompt: prompt, system: system, schema: schema, temperature: temperature)
        }, language: aiLanguage)
    }

    private func examGenerate(prompt: String, system: String, schema: [String: Any], temperature: Double) async -> Result<String, AIError> {
        guard let key = apiKey else { return .failure(.missingAPIKey) }
        guard let model = selectedModel else { return .failure(.noModelSelected) }
        let result = await ai.generateJSON(prompt: prompt, systemInstruction: system, schema: schema, apiKey: key, model: model, temperature: temperature)
        // Fix the selection so the next try works.
        if case .failure(.modelUnavailable) = result { await repairMissingModel() }
        return result
    }

    /// Puts the words an exam got wrong (fully or partly) on the Need Review list. Returns how many were flagged.
    @discardableResult
    func flagExamMisses(_ records: [ExamAnswerRecord]) -> Int {
        var worst: [UUID: Double] = [:]
        for record in records where !record.isCorrect {
            for id in record.words { worst[id] = min(worst[id] ?? 1, record.score) }
        }
        var flags: [ReviewFlag] = []
        for (id, score) in worst {
            guard let word = repository.word(id: id) else { continue }
            flags.append(ReviewFlag(wordID: id, headword: word.spanish, translation: word.translation, score: 1 - score, note: "Missed in an exam", sourceArtifactID: nil))
        }
        return review.flag(flags, now: Date())
    }
}
