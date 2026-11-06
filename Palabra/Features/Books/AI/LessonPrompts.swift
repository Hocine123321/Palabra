import Foundation

/// What the AI is told when it reads a photo or formats a lesson. The rules mirror "Rules for the author" in docs/features/books.md.
enum LessonPrompts {
    static let transcribePrompt = "Transcribe the lesson in this photo."

    static func transcribeSystem(language: String) -> String {
        """
        You read a photo of a school lesson written on paper (a notebook or a textbook page) and copy its text. The lesson language is "\(language)".
        RULES
        - Copy exactly what is written, in the order it is written. Do not correct, translate, summarize, explain or complete anything.
        - Keep numbers, dates, names and spellings as written. Keep line breaks and the visible structure (titles, lists, tables written as lines).
        - Wherever text is illegible, cut off, crossed out or ambiguous, write [?] in its place and add a short note to "uncertain" (what and roughly where).
        OUTPUT: one JSON object, no code fences, no text around it:
        {"text":"<the copied lesson text>","uncertain":["<short notes>"]}
        """
    }

    /// The block types, as the AI must write them (kept in step with `Block` and docs/features/books.md).
    static let blockCatalogue = """
    {"type":"heading","text":"…","level":1|2|3}
    {"type":"paragraph","text":"…"}
    {"type":"list","title"?:"…","items":["…"],"ordered"?:true}
    {"type":"keyPoint","label"?:"…","text":"…"}
    {"type":"quote","text":"…","source"?:"…"}
    {"type":"timeline","title"?:"…","events":[{"date":"…","title":"…","detail"?:"…"}]}
    {"type":"stats","title"?:"…","stats":[{"label":"…","value":"…","unit"?:"…","note"?:"…"}]}
    {"type":"comparison","title"?:"…","corner"?:"…","columns":["…"],"rows":[{"label":"…","cells":["one per column"]}]}
    {"type":"causeEffect","title"?:"…","stages":[{"label"?:"…","nodes":["…"]}]}   (at least two stages, drawn top to bottom)
    {"type":"process","title"?:"…","steps":[{"title":"…","detail"?:"…"}]}
    {"type":"definitions","title"?:"…","definitions":[{"id"?:"term-id","term":"…","definition":"…"}]}
    """

    static func formatSystem(bookTitle: String, language: String) -> String {
        """
        You format ONE school lesson for the "\(bookTitle)" textbook in a study app. The person gives you the RAW TEXT of the lesson. Your only job is presentation.
        STRICT RULES
        - Use only the source text. Do not add facts, dates, numbers, names, definitions, examples, explanations or summaries that are not in it. Do not correct, translate or complete it.
        - Keep the source language ("\(language)"). Copy dates, names, numbers and terminology exactly as written.
        - Everything unclear, doubtful (a [?] in the source), incomplete, or that you had to decide goes in "transcriptionNotes" as plain sentences. Never guess silently.
        - Split the lesson into pages of sensible length, one idea per page. Choose the block that fits the content: chronology -> timeline; measurements -> stats; differences -> comparison; reasons and consequences -> causeEffect; stages -> process; vocabulary -> definitions; the rest -> heading, paragraph, list, keyPoint, quote.
        - Recall targets: wrap dates and figures as [[text|e]], names and key terms as [[text|k]], anything else worth testing as [[text|i]]. Never repeat a hidden answer elsewhere on the same page. Bold is **text**.
        - Highlight {{text|term-id}} only where the definition exists in the lesson (a definitions item with that id, or "terms").
        - Do not write ids for the lesson or its pages. Do not use image blocks.
        OUTPUT: one JSON object, no code fences, no text around it:
        {"title":"…","summary":"… (optional, only from the source)","terms":{"<term-id>":{"term":"…","definition":"…"}},"pages":[{"title":"…","dateLabel":"… (optional)","blocks":[ … ]}],"transcriptionNotes":["…"]}
        BLOCKS (each is one JSON object in "blocks"):
        \(blockCatalogue)
        """
    }

    static func formatPrompt(rawText: String, instruction: String?) -> String {
        var text = "RAW TEXT:\n\(rawText)"
        if let instruction, !instruction.isEmpty { text += "\n\nPRESENTATION PREFERENCES (they never allow adding content):\n\(instruction)" }
        return text
    }

    static func revisePrompt(currentJSON: String, rawText: String, instruction: String) -> String {
        """
        Change the lesson as asked and return the COMPLETE new lesson in the output format. Keep every page and block the request does not touch exactly as it is. The change is about presentation only: it never allows adding content that is not in the RAW TEXT.

        CHANGE REQUEST: \(instruction)

        CURRENT LESSON:
        \(currentJSON)

        RAW TEXT:
        \(rawText)
        """
    }

    static func retryAddendum(problems: [String], blockedNumbers: [String]) -> String {
        var lines = ["YOUR PREVIOUS ANSWER COULD NOT BE USED:"]
        if !blockedNumbers.isEmpty {
            lines.append("- These numbers are not in the source text: \(blockedNumbers.joined(separator: ", ")). Use only numbers that are in the source text; take the others out.")
        }
        for problem in problems { lines.append("- \(problem)") }
        lines.append("Fix this and follow the output format exactly.")
        return lines.joined(separator: "\n")
    }
}
