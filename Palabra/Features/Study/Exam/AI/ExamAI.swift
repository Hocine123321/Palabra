import Foundation

/// What the AI says after an exam: a summary, a tip per missed word, and what to practise next.
struct ExamCoachReport: Equatable, Sendable {
    struct Tip: Equatable, Sendable {
        let word: String
        let tip: String
    }

    var summary: String
    var tips: [Tip]
    var focus: String
}

enum ExamAILimits {
    static let maxWords = 15
    static let maxSentence = 240
    static let maxFeedback = 400
    static let maxSummary = 500
    static let maxTips = 6
    static let maxTip = 240
    static let maxMissesSent = 12
}

/// The optional AI side of an exam: fresh sentences, checking written answers, and a coach's summary. Everything goes
/// through one `generate` call (the app's AI client, key and model), so nothing here talks to the network directly.
/// An exam never needs this: without it every question comes from the person's own words.
struct ExamAI: ExamGrading {
    /// prompt, system instruction, response schema, temperature.
    typealias Generate = @MainActor (String, String, [String: Any], Double) async -> Result<String, AIError>

    let generate: Generate
    /// The language explanations and feedback are written in.
    let language: SupportedLanguage

    // MARK: - Fresh sentences

    func freshItems(for words: [ExamWord]) async -> Result<[UUID: ExamAIItem], AIError> {
        let limited = Array(words.prefix(ExamAILimits.maxWords))
        guard !limited.isEmpty else { return .success([:]) }
        let list = limited.enumerated().map { index, word in
            "\(index + 1). \(word.headword) = \(word.translations.prefix(2).joined(separator: " / "))\(word.partOfSpeech.isEmpty ? "" : " (\(word.partOfSpeech))")"
        }.joined(separator: "\n")
        let result = await generate(
            "Words:\n\(list)",
            ExamPrompts.freshItemsInstruction(language: language),
            ExamPrompts.freshItemsSchema,
            0.7
        )
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text): return Self.parseItems(text, words: limited)
        }
    }

    nonisolated static func parseItems(_ text: String, words: [ExamWord]) -> Result<[UUID: ExamAIItem], AIError> {
        struct Payload: Decodable {
            struct Item: Decodable {
                let word: String
                let cloze: String?
                let clozeAnswer: String?
                let clozeEnglish: String?
                let translatePrompt: String?
                let reference: String?
            }
            let items: [Item]
        }
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.malformedResponse)
        }
        var byHeadword: [String: ExamWord] = [:]
        for word in words { byHeadword[AnswerMatcher.fold(word.headword)] = word }
        var result: [UUID: ExamAIItem] = [:]
        for item in payload.items {
            guard let word = byHeadword[AnswerMatcher.fold(item.word)], result[word.id] == nil else { continue }
            var clean = ExamAIItem(wordID: word.id)
            if let cloze = clip(item.cloze), cloze.contains(ClozeFinder.blank), let answer = clip(item.clozeAnswer) {
                // Exactly one blank, so the answer fits one place.
                if cloze.components(separatedBy: ClozeFinder.blank).count == 2 {
                    clean.cloze = cloze
                    clean.clozeAnswer = answer
                    clean.clozeEnglish = clip(item.clozeEnglish)
                }
            }
            if let prompt = clip(item.translatePrompt), let reference = clip(item.reference) {
                clean.translatePrompt = prompt
                clean.reference = reference
            }
            if clean.cloze != nil || clean.translatePrompt != nil { result[word.id] = clean }
        }
        return .success(result)
    }

    // MARK: - Checking written answers

    func grade(question: ExamQuestion, answer: String) async -> Result<ExamAIGrade, AIError> {
        let task: String
        switch question.kind {
        case .translate: task = "Translate into Spanish: \(question.subject)\nThe word that should be used: \(question.headword)"
        default: task = "Write a Spanish sentence that uses the word: \(question.headword) (\(question.hint ?? ""))"
        }
        var prompt = "Task: \(task)\n"
        if case .written(let reference?) = question.format { prompt += "Model answer: \(reference)\n" }
        prompt += "Student's answer: \(String(answer.prefix(ExamAILimits.maxSentence * 2)))"
        let result = await generate(prompt, ExamPrompts.gradeInstruction(language: language), ExamPrompts.gradeSchema, 0)
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text):
            guard let grade = Self.parseGrade(text) else { return .failure(.malformedResponse) }
            return .success(grade)
        }
    }

    nonisolated static func parseGrade(_ text: String) -> ExamAIGrade? {
        struct Payload: Decodable {
            let score: Double
            let corrected: String?
            let feedback: String?
        }
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.score.isFinite else { return nil }
        return ExamAIGrade(
            score: min(max(payload.score, 0), 1),
            corrected: clip(payload.corrected, limit: ExamAILimits.maxSentence),
            feedback: clip(payload.feedback, limit: ExamAILimits.maxFeedback) ?? ""
        )
    }

    // MARK: - Coach

    func coach(records: [ExamAnswerRecord], percent: Int) async -> Result<ExamCoachReport, AIError> {
        let missed = records.filter { !$0.isCorrect }.prefix(ExamAILimits.maxMissesSent)
        guard !missed.isEmpty else {
            return .success(ExamCoachReport(summary: "", tips: [], focus: ""))
        }
        let lines = missed.map { record in
            "- \(record.headword) [\(record.kindRaw)]: answered \"\(String(record.given.prefix(120)))\", expected \"\(String(record.expected.prefix(120)))\""
        }.joined(separator: "\n")
        let result = await generate(
            "Score: \(percent)%\nMistakes:\n\(lines)",
            ExamPrompts.coachInstruction(language: language),
            ExamPrompts.coachSchema,
            0.4
        )
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text):
            guard let report = Self.parseCoach(text) else { return .failure(.malformedResponse) }
            return .success(report)
        }
    }

    nonisolated static func parseCoach(_ text: String) -> ExamCoachReport? {
        struct Payload: Decodable {
            struct Tip: Decodable {
                let word: String
                let tip: String
            }
            let summary: String
            let tips: [Tip]?
            let focus: String?
        }
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let tips = (payload.tips ?? []).prefix(ExamAILimits.maxTips).compactMap { tip -> ExamCoachReport.Tip? in
            guard let word = clip(tip.word, limit: 60), let body = clip(tip.tip, limit: ExamAILimits.maxTip) else { return nil }
            return ExamCoachReport.Tip(word: word, tip: body)
        }
        let summary = clip(payload.summary, limit: ExamAILimits.maxSummary) ?? ""
        guard !summary.isEmpty || !tips.isEmpty else { return nil }
        return ExamCoachReport(summary: summary, tips: Array(tips), focus: clip(payload.focus, limit: ExamAILimits.maxTip) ?? "")
    }

    // MARK: - Helpers

    nonisolated private static func clip(_ text: String?, limit: Int = ExamAILimits.maxSentence) -> String? {
        guard let text else { return nil }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ExamPrompts {
    private static func languageName(_ language: SupportedLanguage) -> String { language == .arabic ? "Arabic" : "English" }

    static func freshItemsInstruction(language: SupportedLanguage) -> String {
        """
        You write practice material for a student learning Spanish. For every numbered word in the list, return one item.
        - "word": the Spanish word exactly as listed.
        - "cloze": a natural Spanish sentence of 6 to 12 words that uses the word (or a conjugated or inflected form of it) once. Replace that one use with exactly "\(ClozeFinder.blank)". Everyday situations, a different one for each word.
        - "clozeAnswer": the exact text that belongs in the blank, as it must be written in the sentence.
        - "clozeEnglish": the whole sentence translated into \(languageName(language)).
        - "translatePrompt": a different short sentence (5 to 10 words) in \(languageName(language)) that a student can translate into Spanish using the word.
        - "reference": a correct Spanish translation of translatePrompt that uses the word.
        Use simple, correct, neutral Spanish. No slang. Respond with JSON only, matching the schema.
        """
    }

    static let freshItemsSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["items"],
        "properties": [
            "items": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "propertyOrdering": ["word", "cloze", "clozeAnswer", "clozeEnglish", "translatePrompt", "reference"],
                    "properties": [
                        "word": ["type": "STRING"],
                        "cloze": ["type": "STRING"],
                        "clozeAnswer": ["type": "STRING"],
                        "clozeEnglish": ["type": "STRING"],
                        "translatePrompt": ["type": "STRING"],
                        "reference": ["type": "STRING"],
                    ],
                    "required": ["word", "cloze", "clozeAnswer", "clozeEnglish", "translatePrompt", "reference"],
                ],
            ],
        ],
        "required": ["items"],
    ]

    static func gradeInstruction(language: SupportedLanguage) -> String {
        """
        You are a patient Spanish teacher marking one answer from a student. The task and the student's answer are given.
        Score from 0 to 1:
        - 1.0: correct, natural Spanish that does the task (uses the required word or a correct form of it).
        - 0.7: the meaning is right but there is a small mistake (an accent, a gender or number agreement, a preposition).
        - 0.4: understandable, but with a real grammar mistake, or it hardly uses the required word.
        - 0.0: wrong, not Spanish, empty, or it ignores the task.
        Accept any correct answer, not only the model answer. Do not mark down a different but correct word order or word choice.
        "corrected": the student's sentence written correctly in Spanish, or empty when it was already right.
        "feedback": one or two short sentences in \(languageName(language)) saying what was good and the single most useful correction. Respond with JSON only, matching the schema.
        """
    }

    static let gradeSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["score", "corrected", "feedback"],
        "properties": [
            "score": ["type": "NUMBER"],
            "corrected": ["type": "STRING"],
            "feedback": ["type": "STRING"],
        ],
        "required": ["score", "corrected", "feedback"],
    ]

    static func coachInstruction(language: SupportedLanguage) -> String {
        """
        You are a friendly Spanish coach looking at the mistakes a student made in a vocabulary exam. Each line is a missed question: the word, the kind of question, what the student answered and what was expected.
        Write in \(languageName(language)).
        - "summary": two or three sentences: what went well, and what the mistakes have in common (a pattern such as accents, verb forms, false friends, gender).
        - "tips": one short tip for each of the most useful words (at most \(ExamAILimits.maxTips)): a memory trick, a contrast with a similar word, or a usage note. "word" is the Spanish word.
        - "focus": one sentence on what to practise next.
        Be specific and encouraging, never harsh. Respond with JSON only, matching the schema.
        """
    }

    static let coachSchema: [String: Any] = [
        "type": "OBJECT",
        "propertyOrdering": ["summary", "tips", "focus"],
        "properties": [
            "summary": ["type": "STRING"],
            "tips": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "propertyOrdering": ["word", "tip"],
                    "properties": ["word": ["type": "STRING"], "tip": ["type": "STRING"]],
                    "required": ["word", "tip"],
                ],
            ],
            "focus": ["type": "STRING"],
        ],
        "required": ["summary", "tips", "focus"],
    ]
}
