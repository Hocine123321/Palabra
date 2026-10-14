import Foundation

/// Reads a problem from a photo with Gemini (the person's own key). Far better than on-device OCR at handwriting,
/// fractions, roots, integrals and tables, because the model reads the maths, not just the glyphs.
struct GeminiTextRecognizer: TextRecognizer {
    let link: GeminiLink

    static let maxTextLength = 2_000

    func recognize(imageData: Data) async -> Result<String, RecognitionError> {
        guard let credentials = await link.credentials() else { return .failure(.unavailable) }
        guard let image = PhotoPreparer.prepare(imageData) else { return .failure(.unreadable) }
        // One try: if Gemini is offline or busy the on-device reader should answer at once, not after a retry countdown.
        let client = (credentials.ai as? ResilientAIClient)?.failingFast() ?? credentials.ai
        let result = await client.generateJSON(
            prompt: Self.prompt,
            image: image,
            systemInstruction: Self.instruction,
            schema: Self.schema,
            apiKey: credentials.apiKey,
            model: credentials.model,
            temperature: 0
        )
        switch result {
        case .failure: return .failure(.unavailable)
        case .success(let text): return Self.parse(text)
        }
    }

    // MARK: Prompt

    static let prompt = "Copy the problem in this photo."

    static let instruction = """
    You read a photo of a maths or science problem and copy it out as plain text. You never solve it, explain it or add anything.

    Rules:
    - Copy exactly what is written, in the language it is written in. Keep the instruction words ("Solve", "Factor", "Find") when they are there.
    - Plain keyboard notation only. No LaTeX, no Markdown, no code fences.
    - Powers with ^ (x^2), square roots as sqrt(x), fractions as (a)/(b), multiplication as *, pi for the constant, absolute value as |x|.
    - An integral becomes "integrate f from a to b" (or just "integrate f" with no limits), a derivative becomes "derivative of f", a limit becomes "limit of f as x -> a".
    - Several equations that belong together go on one line, separated by commas.
    - Several unrelated problems: copy only the first one, or the one that is circled or underlined.
    - Ignore page furniture: numbering, margins, scribbles, other people's working.
    - If part of it is unreadable, write what you can; use ? only for a single character you cannot make out.
    - If there is no problem or text in the photo, answer found = false.
    """

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "found": ["type": "BOOLEAN", "description": "True when the photo contains a problem or text to copy."],
            "text": ["type": "STRING", "description": "The problem as plain text, one line where possible."],
        ],
        "required": ["found", "text"],
    ]

    // MARK: Parsing

    private struct Reply: Decodable {
        let found: Bool?
        let text: String?
    }

    static func parse(_ json: String) -> Result<String, RecognitionError> {
        guard let data = json.data(using: .utf8), let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .failure(.unavailable)
        }
        let text = (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.found == false || text.isEmpty { return .failure(.nothingFound) }
        return .success(String(text.prefix(maxTextLength)))
    }
}

/// Gemini first (when a key and model are set), the on-device reader when Gemini is off, offline or fails.
struct FallbackTextRecognizer: TextRecognizer {
    let primary: TextRecognizer
    let fallback: TextRecognizer

    func recognize(imageData: Data) async -> Result<String, RecognitionError> {
        switch await primary.recognize(imageData: imageData) {
        case .success(let text):
            return .success(text)
        case .failure(.nothingFound):
            // Gemini looked and saw nothing; on-device OCR may still pick up a line of print.
            if case .success(let text) = await fallback.recognize(imageData: imageData) { return .success(text) }
            return .failure(.nothingFound)
        case .failure:
            return await fallback.recognize(imageData: imageData)
        }
    }
}
