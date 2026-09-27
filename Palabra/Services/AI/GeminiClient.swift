import Foundation

/// Talks to the Google Generative Language REST API (`v1beta`). The API key
/// goes only in the `x-goog-api-key` header, never the URL.
final class GeminiClient: AIClient {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        var all: [AIModel] = []
        var pageToken: String?
        repeat {
            var comps = URLComponents(url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            comps.queryItems = items
            var request = URLRequest(url: comps.url!)
            request.timeoutInterval = 30
            request.setValue(apiKey.trimmed, forHTTPHeaderField: "x-goog-api-key")

            switch await perform(request) {
            case .failure(let error):
                return .failure(error)
            case .success(let data):
                guard let page = try? JSONDecoder().decode(ModelsPage.self, from: data) else {
                    return .failure(.malformedResponse)
                }
                let usable = (page.models ?? []).filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
                all.append(contentsOf: usable.map {
                    AIModel(id: $0.name, displayName: $0.displayName ?? $0.name, description: $0.description,
                            inputTokenLimit: $0.inputTokenLimit, outputTokenLimit: $0.outputTokenLimit)
                })
                pageToken = page.nextPageToken
            }
        } while pageToken != nil
        return .success(all)
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        let maxTokens = min(8192, model.outputTokenLimit ?? 8192)
        let firstBody = ResponseSchema.wordRequestBody(word: input, systemInstruction: Prompts.wordSystemInstruction(for: language), maxOutputTokens: maxTokens, useSchema: true)

        switch await callGenerate(model: model, apiKey: apiKey, body: firstBody, timeout: 60) {
        case .success(let text):
            return decodeAndValidate(text, language: language)
        case .failure(let error) where shouldRetryWithoutSchema(error):
            let fallbackBody = ResponseSchema.wordRequestBody(word: input, systemInstruction: Prompts.wordSystemInstructionWithSchemaDescribed(for: language), maxOutputTokens: maxTokens, useSchema: false)
            switch await callGenerate(model: model, apiKey: apiKey, body: fallbackBody, timeout: 60) {
            case .success(let text): return decodeAndValidate(text, language: language)
            case .failure(let error2): return .failure(error2)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        let maxTokens = min(4096, model.outputTokenLimit ?? 4096)
        var contents: [[String: Any]] = ChatHistoryBuilder.build(from: history).map {
            ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]]
        }
        contents.append(["role": "user", "parts": [["text": newMessage]]])
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": Prompts.chatSystemInstruction(for: word, language: language)]]],
            "contents": contents,
            "generationConfig": ["temperature": 0.6, "maxOutputTokens": maxTokens]
        ]
        switch await callGenerate(model: model, apiKey: apiKey, body: body, timeout: 45) {
        case .success(let text):
            let trimmed = text.trimmed
            return trimmed.isEmpty ? .failure(.malformedResponse) : .success(trimmed)
        case .failure(let error):
            return .failure(error)
        }
    }

    func generateFlashcards(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[FlashcardDraft], AIError> {
        let maxTokens = min(8192, model.outputTokenLimit ?? 8192)
        let instruction = Prompts.flashcardSystemInstruction(subject: subject, for: language)
        let body = ResponseSchema.notesRequestBody(notes: notes, systemInstruction: instruction, schema: ResponseSchema.flashcardArraySchema, maxOutputTokens: maxTokens, useSchema: true)

        switch await callGenerate(model: model, apiKey: apiKey, body: body, timeout: 60) {
        case .success(let text):
            return decodeArray(text)
        case .failure(let error) where shouldRetryWithoutSchema(error):
            let describedInstruction = instruction + "\n\nRespond with a single JSON array and nothing else — no code fences, no commentary — of objects shaped {\"front\": string, \"back\": string, \"hint\": string (optional)}."
            let fallbackBody = ResponseSchema.notesRequestBody(notes: notes, systemInstruction: describedInstruction, schema: ResponseSchema.flashcardArraySchema, maxOutputTokens: maxTokens, useSchema: false)
            switch await callGenerate(model: model, apiKey: apiKey, body: fallbackBody, timeout: 60) {
            case .success(let text): return decodeArray(text)
            case .failure(let error2): return .failure(error2)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func generateQuiz(from notes: String, subject: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<[QuizQuestion], AIError> {
        let maxTokens = min(8192, model.outputTokenLimit ?? 8192)
        let instruction = Prompts.quizSystemInstruction(subject: subject, for: language)
        let body = ResponseSchema.notesRequestBody(notes: notes, systemInstruction: instruction, schema: ResponseSchema.quizArraySchema, maxOutputTokens: maxTokens, useSchema: true)

        switch await callGenerate(model: model, apiKey: apiKey, body: body, timeout: 60) {
        case .success(let text):
            return decodeArray(text)
        case .failure(let error) where shouldRetryWithoutSchema(error):
            let describedInstruction = instruction + "\n\nRespond with a single JSON array and nothing else — no code fences, no commentary — of objects shaped {\"question\": string, \"options\": [string] (exactly 4), \"correctIndex\": number, \"explanation\": string (optional)}."
            let fallbackBody = ResponseSchema.notesRequestBody(notes: notes, systemInstruction: describedInstruction, schema: ResponseSchema.quizArraySchema, maxOutputTokens: maxTokens, useSchema: false)
            switch await callGenerate(model: model, apiKey: apiKey, body: fallbackBody, timeout: 60) {
            case .success(let text): return decodeArray(text)
            case .failure(let error2): return .failure(error2)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Shared plumbing

    private func callGenerate(model: AIModel, apiKey: String, body: [String: Any], timeout: TimeInterval) async -> Result<String, AIError> {
        let url = baseURL.appendingPathComponent("\(model.id):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(apiKey.trimmed, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        switch await perform(request) {
        case .failure(let error): return .failure(error)
        case .success(let data): return extractText(from: data)
        }
    }

    private func perform(_ request: URLRequest) async -> Result<Data, AIError> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unknown(nil, "No HTTP response"))
            }
            if (200..<300).contains(http.statusCode) { return .success(data) }
            return .failure(mapError(status: http.statusCode, data: data))
        } catch let urlError as URLError {
            return .failure(mapURLError(urlError))
        } catch {
            return .failure(.unknown(nil, error.localizedDescription))
        }
    }

    private func mapURLError(_ error: URLError) -> AIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .unknown(nil, error.localizedDescription)
        }
    }

    private func mapError(status: Int, data: Data) -> AIError {
        let message = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error?.message ?? ""
        switch status {
        case 400:
            let lower = message.lowercased()
            if lower.contains("api key not valid") || lower.contains("api_key_invalid") {
                return .invalidAPIKey
            }
            return .unknown(status, message.isEmpty ? "Bad request" : message)
        case 403:
            return .permissionDenied
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError(status)
        default:
            return .unknown(status, message)
        }
    }

    private func shouldRetryWithoutSchema(_ error: AIError) -> Bool {
        guard case .unknown(400, let message) = error else { return false }
        let lower = message.lowercased()
        return lower.contains("response_schema") || lower.contains("responseschema")
            || lower.contains("response_mime_type") || lower.contains("system_instruction")
    }

    private func extractText(from data: Data) -> Result<String, AIError> {
        guard let decoded = try? JSONDecoder().decode(GeminiGenerateResponse.self, from: data) else {
            return .failure(.malformedResponse)
        }
        if let blockReason = decoded.promptFeedback?.blockReason {
            return .failure(.blocked(blockReason))
        }
        guard let candidate = decoded.candidates?.first else {
            return .failure(.malformedResponse)
        }
        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap { $0.text }
            .joined()
        if text.isEmpty {
            return .failure(candidate.finishReason == "MAX_TOKENS" ? .truncated : .malformedResponse)
        }
        if candidate.finishReason == "SAFETY" { return .failure(.blocked(candidate.finishReason)) }
        if candidate.finishReason == "MAX_TOKENS" { return .failure(.truncated) }
        return .success(text)
    }

    private func decodeAndValidate(_ text: String, language: SupportedLanguage) -> Result<WordContent, AIError> {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8),
              var content = try? JSONDecoder().decode(WordContent.self, from: data) else {
            return .failure(.malformedResponse)
        }
        content.contentLanguage = language
        return ContentValidator.validate(content)
    }

    private func decodeArray<T: Decodable>(_ text: String) -> Result<[T], AIError> {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8),
              let items = try? JSONDecoder().decode([T].self, from: data),
              !items.isEmpty else {
            return .failure(.malformedResponse)
        }
        return .success(items)
    }

    private func stripCodeFences(_ text: String) -> String {
        var t = text.trimmed
        guard t.hasPrefix("```") else { return t }
        if let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
        }
        if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        return t.trimmed
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Wire types (Google's JSON shape, not the app's domain types)

private struct ModelsPage: Decodable {
    struct Entry: Decodable {
        var name: String
        var displayName: String?
        var description: String?
        var inputTokenLimit: Int?
        var outputTokenLimit: Int?
        var supportedGenerationMethods: [String]?
    }
    var models: [Entry]?
    var nextPageToken: String?
}

private struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                var text: String?
                var thought: Bool?
            }
            var parts: [Part]?
        }
        var content: Content?
        var finishReason: String?
    }
    struct PromptFeedback: Decodable {
        var blockReason: String?
    }
    var candidates: [Candidate]?
    var promptFeedback: PromptFeedback?
}

private struct GeminiErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        var code: Int?
        var message: String?
        var status: String?
    }
    var error: ErrorBody?
}
