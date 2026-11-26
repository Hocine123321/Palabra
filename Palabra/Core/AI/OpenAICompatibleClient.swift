import Foundation

/// OpenRouter and Groq: both take the OpenAI chat-completions protocol (`/models`, `/chat/completions`, a Bearer key), so one
/// client serves them, told apart by `provider`. It answers every `AIClient` call the way `GeminiClient` does, so every
/// screen works unchanged. Pronunciation is the one thing it cannot do.
final class OpenAICompatibleClient: AIClient, RetryHintProviding, @unchecked Sendable {
    let provider: AIProvider
    private let session: URLSession
    private let baseURL: URL
    private let hintLock = NSLock()
    private var lastHint: TimeInterval?

    init(provider: AIProvider, session: URLSession = .shared, baseURL: URL? = nil) {
        precondition(provider != .gemini, "Gemini has its own client")
        self.provider = provider
        self.session = session
        self.baseURL = baseURL ?? provider.openAIBaseURL!
    }

    func takeRetryHint() -> TimeInterval? {
        hintLock.lock(); defer { hintLock.unlock() }
        let hint = lastHint
        lastHint = nil
        return hint
    }

    // MARK: AIClient

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 30
        authorize(&request, apiKey: apiKey)
        // OpenRouter lists its models to anyone, so a wrong key would look fine here: ask about the key itself.
        if provider == .openRouter, case .failure(let error) = await checkKey(apiKey), error == .invalidAPIKey || error == .offline || error == .timeout {
            return .failure(error)
        }
        switch await perform(request) {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            guard let page = try? JSONDecoder().decode(ModelsPage.self, from: data) else { return .failure(.malformedResponse) }
            return .success((page.data ?? []).compactMap(model(from:)))
        }
    }

    private func checkKey(_ apiKey: String) async -> Result<Data, AIError> {
        var request = URLRequest(url: baseURL.appendingPathComponent("key"))
        request.timeoutInterval = 20
        authorize(&request, apiKey: apiKey)
        return await perform(request)
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        let system = VocabularyPrompts.wordSystemInstructionWithSchemaDescribed(for: language)
        let result = await completeJSON(
            model: model, apiKey: apiKey,
            messages: [message("system", system), message("user", input)],
            temperature: 0.7, maxTokens: Self.cap(8192, for: model), jsonObject: true, timeout: 60
        )
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text): return decodeWord(text, language: language)
        }
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        var messages = [message("system", VocabularyPrompts.chatSystemInstruction(for: word, language: language))]
        for turn in ChatHistoryBuilder.build(from: history) {
            messages.append(message(turn.role == .user ? "user" : "assistant", turn.text))
        }
        messages.append(message("user", newMessage))
        let result = await complete(model: model, apiKey: apiKey, messages: messages, temperature: 0.6, maxTokens: Self.cap(4096, for: model), jsonObject: false, timeout: 45)
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .failure(.malformedResponse) : .success(trimmed)
        }
    }

    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> {
        .failure(.unknown(nil, "Pronunciation needs a Google Gemini key."))
    }

    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        await structured(prompt: prompt, image: nil, systemInstruction: systemInstruction, schema: schema, apiKey: apiKey, model: model, temperature: temperature)
    }

    func generateJSON(prompt: String, image: AIImage, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        await structured(prompt: prompt, image: image, systemInstruction: systemInstruction, schema: schema, apiKey: apiKey, model: model, temperature: temperature)
    }

    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> {
        let input = (try? JSONEncoder().encode(words)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let result = await generateJSON(
            prompt: input,
            systemInstruction: LibraryOrganizerPrompts.systemInstruction(existingCategories: existingCategories, settings: settings, language: language),
            schema: LibraryOrganizerPrompts.batchSchema,
            apiKey: apiKey, model: model, temperature: 0.2
        )
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let text):
            guard let data = text.data(using: .utf8), let decoded = try? JSONDecoder().decode(OrganizerBatchResult.self, from: data) else {
                return .failure(.malformedResponse)
            }
            return .success(decoded)
        }
    }

    // MARK: Structured calls

    /// The schema Gemini takes as a `responseSchema` has no equivalent here, so it is described to the model in words and
    /// the reply is requested as a JSON object; a model that refuses JSON mode is asked again without it.
    private func structured(prompt: String, image: AIImage?, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        let maxTokens = GeminiClient.structuredMaxTokens(model: model, requested: ArtifactOutputBudget.requestedTokens)
        let timeout = GeminiClient.structuredTimeout(maxTokens: maxTokens)
        var system = systemInstruction
        var jsonObject = false
        if let schema, let described = Self.describe(schema) {
            system += "\n\nReply with ONE JSON object and nothing else (no Markdown, no code fences). It must match this schema (types are written OpenAPI style):\n" + described
            jsonObject = (schema["type"] as? String)?.uppercased() == "OBJECT"
        }
        var user: [String: Any] = message("user", prompt)
        if let image {
            user = [
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"]],
                    ["type": "text", "text": prompt],
                ] as [[String: Any]],
            ]
        }
        let messages = [message("system", system), user]
        let result = await completeJSON(model: model, apiKey: apiKey, messages: messages, temperature: temperature, maxTokens: maxTokens, jsonObject: jsonObject, timeout: timeout)
        return result.map { CodeFence.extractJSON($0) }
    }

    /// Asks for a JSON object; a model that refuses JSON mode is asked again without it (the prompt already says "JSON").
    private func completeJSON(model: AIModel, apiKey: String, messages: [[String: Any]], temperature: Double, maxTokens: Int, jsonObject: Bool, timeout: TimeInterval) async -> Result<String, AIError> {
        let first = await complete(model: model, apiKey: apiKey, messages: messages, temperature: temperature, maxTokens: maxTokens, jsonObject: jsonObject, timeout: timeout)
        if case .failure(let error) = first, jsonObject, Self.refusesJSONMode(error) {
            return await complete(model: model, apiKey: apiKey, messages: messages, temperature: temperature, maxTokens: maxTokens, jsonObject: false, timeout: timeout)
        }
        return first
    }

    static func describe(_ schema: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(schema),
              let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The model (or its host) does not do JSON mode: asking again without it can work.
    static func refusesJSONMode(_ error: AIError) -> Bool {
        guard case .unknown(let status, let message) = error, status == 400 || status == 422 else { return false }
        let lower = message.lowercased()
        return lower.contains("response_format") || lower.contains("json_validate_failed") || lower.contains("json mode")
            || lower.contains("json_object") || lower.contains("failed to generate json")
    }

    /// Never ask for more than the model can write.
    static func cap(_ wanted: Int, for model: AIModel) -> Int {
        min(wanted, model.outputTokenLimit ?? wanted)
    }

    // MARK: Request / response

    private func message(_ role: String, _ text: String) -> [String: Any] { ["role": role, "content": text] }

    private func authorize(_ request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        if provider == .openRouter {
            // OpenRouter shows these in the person's activity page.
            request.setValue("https://github.com/Hocine123321/Palabra", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Palabra", forHTTPHeaderField: "X-Title")
        }
    }

    /// One chat-completions call. A host that says `max_tokens` is more than the model can write (a model list that gave no
    /// limit) is asked again with a smaller one, instead of failing a request that would have worked.
    private func complete(model: AIModel, apiKey: String, messages: [[String: Any]], temperature: Double, maxTokens: Int, jsonObject: Bool, timeout: TimeInterval) async -> Result<String, AIError> {
        let first = await send(model: model, apiKey: apiKey, messages: messages, temperature: temperature, maxTokens: maxTokens, jsonObject: jsonObject, timeout: timeout)
        if case .failure(let error) = first, Self.refusesTokenLimit(error), maxTokens > Self.saferMaxTokens {
            return await send(model: model, apiKey: apiKey, messages: messages, temperature: temperature, maxTokens: Self.saferMaxTokens, jsonObject: jsonObject, timeout: timeout)
        }
        return first
    }

    static let saferMaxTokens = 4096

    static func refusesTokenLimit(_ error: AIError) -> Bool {
        guard case .unknown(let status, let message) = error, status == 400 || status == 422 else { return false }
        let lower = message.lowercased()
        return lower.contains("max_tokens") || lower.contains("max_completion_tokens") || lower.contains("maximum context length")
            || lower.contains("context_length_exceeded")
    }

    private func send(model: AIModel, apiKey: String, messages: [[String: Any]], temperature: Double, maxTokens: Int, jsonObject: Bool, timeout: TimeInterval) async -> Result<String, AIError> {
        var body: [String: Any] = [
            "model": model.id,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        if jsonObject { body["response_format"] = ["type": "json_object"] }
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.unknown(nil, "The request could not be built."))
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, apiKey: apiKey)
        request.httpBody = data
        switch await perform(request, model: model) {
        case .failure(let error): return .failure(error)
        case .success(let reply): return extractText(from: reply)
        }
    }

    static let maxResponseBytes = 24 * 1024 * 1024

    private func perform(_ request: URLRequest, model: AIModel? = nil) async -> Result<Data, AIError> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.unknown(nil, "No HTTP response")) }
            if (200..<300).contains(http.statusCode) {
                guard data.count <= Self.maxResponseBytes else { return .failure(.malformedResponse) }
                // OpenRouter reports some failures with a 200 and an `error` object.
                if let body = try? JSONDecoder().decode(CompletionResponse.self, from: data), let failure = body.error, body.choices == nil {
                    return .failure(mapError(status: failure.code ?? 500, message: failure.message ?? "", retryAfter: nil, model: model))
                }
                return .success(data)
            }
            return .failure(mapError(status: http.statusCode, message: errorMessage(in: data), retryAfter: http.value(forHTTPHeaderField: "Retry-After"), model: model))
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive:
                return .failure(.offline)
            case .timedOut: return .failure(.timeout)
            case .cancelled: return .failure(.cancelled)
            default: return .failure(.unknown(nil, urlError.localizedDescription))
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.unknown(nil, error.localizedDescription))
        }
    }

    private func errorMessage(in data: Data) -> String {
        (try? JSONDecoder().decode(CompletionResponse.self, from: data))?.error?.message ?? ""
    }

    func mapError(status: Int, message: String, retryAfter: String?, model: AIModel?) -> AIError {
        let lower = message.lowercased()
        switch status {
        case 401:
            return .invalidAPIKey
        case 402:
            // OpenRouter: not enough credits for this model.
            return .quotaExhausted
        case 403:
            return .permissionDenied
        case 404:
            return .modelUnavailable(model?.id ?? "")
        case 408:
            return .timeout
        case 429:
            if let seconds = retryAfter.flatMap(Double.init), seconds >= 0, seconds.isFinite {
                hintLock.lock(); lastHint = seconds; hintLock.unlock()
            }
            return Self.isQuotaExhausted(lower) ? .quotaExhausted : .rateLimited
        case 500...599:
            return .serverError(status)
        default:
            return .unknown(status, message.isEmpty ? "Request failed (\(status))" : message)
        }
    }

    /// A spent daily allowance, as opposed to a per-minute limit that clears on its own.
    static func isQuotaExhausted(_ lowercasedMessage: String) -> Bool {
        let m = lowercasedMessage
        if m.contains("per minute") || m.contains("per second") || m.contains("(rpm)") || m.contains("(tpm)") { return false }
        return m.contains("per day") || m.contains("(rpd)") || m.contains("(tpd)") || m.contains("daily")
            || m.contains("insufficient credits") || m.contains("quota")
    }

    private func extractText(from data: Data) -> Result<String, AIError> {
        guard let decoded = try? JSONDecoder().decode(CompletionResponse.self, from: data),
              let choice = decoded.choices?.first else { return .failure(.malformedResponse) }
        // Reasoning models may put their thinking in the reply; only what follows it is the answer.
        let text = Self.withoutThinking(choice.message?.content?.text ?? "")
        if choice.finishReason == "content_filter" { return .failure(.blocked("content_filter")) }
        if choice.finishReason == "length" { return .failure(.truncated) }
        return text.isEmpty ? .failure(.malformedResponse) : .success(text)
    }

    static func withoutThinking(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>"), let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // A reply cut inside its thinking has no answer at all.
        if let open = result.range(of: "<think>") { result.removeSubrange(open.lowerBound..<result.endIndex) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeWord(_ text: String, language: SupportedLanguage) -> Result<WordContent, AIError> {
        let cleaned = CodeFence.extractJSON(text)
        guard let data = cleaned.data(using: .utf8), var content = try? JSONDecoder().decode(WordContent.self, from: data) else {
            return .failure(.malformedResponse)
        }
        content.contentLanguage = language
        return ContentValidator.validate(content)
    }

    // MARK: Models

    private func model(from entry: ModelsPage.Entry) -> AIModel? {
        let id = entry.id
        let lower = id.lowercased()
        let name: String
        var images: Bool?
        switch provider {
        case .groq:
            // Speech, transcription and safety models cannot answer a text request.
            let notChat = ["whisper", "tts", "playai", "orpheus", "guard", "safeguard", "embed"]
            if notChat.contains(where: lower.contains) || entry.active == false { return nil }
            name = id
            images = lower.contains("vision") || lower.contains("llama-4") || lower.contains("scout") || lower.contains("maverick")
        case .openRouter:
            if let outputs = entry.architecture?.outputModalities, !outputs.contains("text") { return nil }
            var title = entry.name ?? id
            if entry.pricing?.isFree == true, !id.hasSuffix(":free") || !title.lowercased().contains("free") { title += " (free)" }
            name = title
            if let inputs = entry.architecture?.inputModalities { images = inputs.contains("image") }
        case .gemini:
            return nil
        }
        return AIModel(
            id: id, displayName: name, description: entry.description,
            inputTokenLimit: entry.contextLength ?? entry.contextWindow,
            outputTokenLimit: entry.maxCompletionTokens ?? entry.topProvider?.maxCompletionTokens,
            provider: provider, acceptsImages: images
        )
    }
}

// MARK: - Wire types

private struct ModelsPage: Decodable {
    struct Entry: Decodable {
        struct Architecture: Decodable {
            var inputModalities: [String]?
            var outputModalities: [String]?
            enum CodingKeys: String, CodingKey { case inputModalities = "input_modalities", outputModalities = "output_modalities" }
        }
        struct Pricing: Decodable {
            var prompt: String?
            var completion: String?
            var isFree: Bool { (Double(prompt ?? "") ?? -1) == 0 && (Double(completion ?? "") ?? -1) == 0 }
        }
        struct TopProvider: Decodable {
            var maxCompletionTokens: Int?
            enum CodingKeys: String, CodingKey { case maxCompletionTokens = "max_completion_tokens" }
        }
        var id: String
        var name: String?
        var description: String?
        var contextLength: Int?
        var contextWindow: Int?
        var maxCompletionTokens: Int?
        var active: Bool?
        var architecture: Architecture?
        var pricing: Pricing?
        var topProvider: TopProvider?
        enum CodingKeys: String, CodingKey {
            case id, name, description, active, architecture, pricing
            case contextLength = "context_length"
            case contextWindow = "context_window"
            case maxCompletionTokens = "max_completion_tokens"
            case topProvider = "top_provider"
        }
    }
    var data: [Entry]?
}

private struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: FlexibleText?
        }
        var message: Message?
        var finishReason: String?
        enum CodingKeys: String, CodingKey { case message, finishReason = "finish_reason" }
    }
    struct Failure: Decodable {
        var message: String?
        var code: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
            // Some hosts send the code as a number, others as a word ("rate_limit_exceeded").
            code = try? c.decodeIfPresent(Int.self, forKey: .code)
        }
        enum CodingKeys: String, CodingKey { case message, code }
    }
    var choices: [Choice]?
    var error: Failure?
}

/// `content` is a string almost everywhere, a list of text parts on some hosts.
private struct FlexibleText: Decodable {
    var text: String
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            text = string
        } else if let parts = try? single.decode([Part].self) {
            text = parts.compactMap(\.text).joined()
        } else {
            text = ""
        }
    }
    struct Part: Decodable { var text: String? }
}
