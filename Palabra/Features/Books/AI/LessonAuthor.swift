import Foundation

enum LessonAuthorError: Error, Equatable {
    case ai(AIError)
    /// The answer was not a lesson even after one retry.
    case malformed(String)
    case nothingRead

    /// Shown to the person (a `LocalizedStringKey` lookup at the call site) for the cases that have no `AIError` message.
    var userMessage: String {
        switch self {
        case .ai(let error): return error.userMessage
        case .malformed: return "The AI's answer wasn't a usable lesson. Try again."
        case .nothingRead: return "Nothing could be read from that photo."
        }
    }
}

struct Transcription: Equatable {
    var text: String
    /// Short notes about text the AI could not read.
    var uncertain: [String]
}

/// A lesson as formatted by the AI, with what the checks found. A draft with problems is still returned (after one retry)
/// so the person can see exactly what is wrong instead of getting nothing.
struct LessonDraft: Equatable {
    var lesson: Lesson
    var report: LessonFaithfulness.Report
    /// Structural problems from `LessonValidator`.
    var problems: [String]

    var isClean: Bool { problems.isEmpty && report.isClean }
}

/// Turns photos and raw text into a lesson. The AI only changes how the text is presented; see `LessonPrompts` for its rules
/// and `LessonFaithfulness` for the check on what comes back.
struct LessonAuthor {
    let ai: AIClient

    func transcribe(photo: AIImage, apiKey: String, model: AIModel, language: String) async -> Result<Transcription, LessonAuthorError> {
        let result = await ai.generateJSON(
            prompt: LessonPrompts.transcribePrompt, image: photo,
            systemInstruction: LessonPrompts.transcribeSystem(language: language),
            schema: nil, apiKey: apiKey, model: model, temperature: 0
        )
        switch result {
        case .failure(let error): return .failure(.ai(error))
        case .success(let text):
            struct Wire: Decodable { var text: String; var uncertain: [String]? }
            guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(CodeFence.extractJSON(text).utf8)) else {
                return .failure(.malformed("the transcription was not JSON"))
            }
            let trimmed = wire.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .failure(.nothingRead) }
            return .success(Transcription(text: trimmed, uncertain: wire.uncertain ?? []))
        }
    }

    func format(rawText: String, bookTitle: String, language: String, instruction: String?, takenLessonIDs: Set<String>, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError> {
        await run(
            prompt: LessonPrompts.formatPrompt(rawText: rawText, instruction: instruction),
            system: LessonPrompts.formatSystem(bookTitle: bookTitle, language: language),
            rawText: rawText, previous: nil, taken: takenLessonIDs, apiKey: apiKey, model: model
        )
    }

    func revise(current: Lesson, rawText: String, instruction: String, bookTitle: String, language: String, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError> {
        let json = (try? LessonCoding.encode(current)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return await run(
            prompt: LessonPrompts.revisePrompt(currentJSON: json, rawText: rawText, instruction: instruction),
            system: LessonPrompts.formatSystem(bookTitle: bookTitle, language: language),
            rawText: rawText, previous: current, taken: [], apiKey: apiKey, model: model
        )
    }

    // MARK: One attempt, plus at most one retry with the concrete problems

    private func run(prompt: String, system: String, rawText: String, previous: Lesson?, taken: Set<String>, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError> {
        var currentPrompt = prompt
        for attempt in 0...1 {
            switch await once(prompt: currentPrompt, system: system, rawText: rawText, previous: previous, taken: taken, apiKey: apiKey, model: model) {
            case .failure(.malformed(let detail)) where attempt == 0:
                currentPrompt = prompt + "\n\n" + LessonPrompts.retryAddendum(problems: ["The answer was not valid lesson JSON (\(detail))."], blockedNumbers: [])
            case .failure(let error):
                return .failure(error)
            case .success(let draft):
                if draft.isClean || attempt == 1 { return .success(draft) }
                currentPrompt = prompt + "\n\n" + LessonPrompts.retryAddendum(problems: draft.problems, blockedNumbers: draft.report.blockedNumbers)
            }
        }
        return .failure(.malformed("no attempt was made")) // unreachable: the loop always returns
    }

    private func once(prompt: String, system: String, rawText: String, previous: Lesson?, taken: Set<String>, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError> {
        let result = await ai.generateJSON(prompt: prompt, systemInstruction: system, schema: nil, apiKey: apiKey, model: model, temperature: 0.2)
        switch result {
        case .failure(let error): return .failure(.ai(error))
        case .success(let text):
            guard let wire = try? JSONDecoder().decode(WireLesson.self, from: Data(CodeFence.extractJSON(text).utf8)) else {
                return .failure(.malformed("it could not be read as a lesson"))
            }
            let raw = Lesson(
                id: "", version: 1, title: wire.title, summary: wire.summary, terms: wire.terms ?? [:],
                pages: wire.pages.map { LessonPage(id: "", title: $0.title, dateLabel: $0.dateLabel, blocks: $0.blocks) },
                transcriptionNotes: wire.transcriptionNotes ?? []
            )
            let lesson = LessonIDs.assign(raw, previous: previous, takenLessonIDs: taken)
            return .success(LessonDraft(lesson: lesson, report: LessonFaithfulness.check(lesson, source: rawText), problems: LessonValidator.problems(in: lesson)))
        }
    }

    /// The AI's lesson JSON: the same as a lesson file, without ids (the app assigns them).
    private struct WireLesson: Decodable {
        var title: String
        var summary: String?
        var terms: [String: TermDefinition]?
        var pages: [WirePage]
        var transcriptionNotes: [String]?
    }

    private struct WirePage: Decodable {
        var title: String
        var dateLabel: String?
        var blocks: [Block]
    }
}
