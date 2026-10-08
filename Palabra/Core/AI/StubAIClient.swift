import Foundation

/// Deterministic `AIClient` for SwiftUI previews and UI tests (`-UITestStub`).
/// Sends "fallo" as the word or a chat message to exercise the failure path.
final class StubAIClient: AIClient {
    static let sampleModels: [AIModel] = [
        AIModel(id: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "Fast and cost-efficient.", inputTokenLimit: 1_000_000, outputTokenLimit: 8192),
        AIModel(id: "models/gemini-2.5-pro", displayName: "Gemini 2.5 Pro", description: "Most capable.", inputTokenLimit: 2_000_000, outputTokenLimit: 8192),
        AIModel(id: "models/gemini-2.5-flash-tts", displayName: "Gemini 2.5 Flash TTS", description: "Fast, natural speech.", inputTokenLimit: 8_000, outputTokenLimit: 8_000)
    ]

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .failure(.invalidAPIKey) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .success(Self.sampleModels)
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        try? await Task.sleep(nanoseconds: 400_000_000)
        if input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(Self.sampleContent(for: input, language: language))
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if newMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(language == .arabic ? "فكّر في \"\(word.word)\" بهذه الطريقة: \(newMessage)" : "Think of \"\(word.word)\" this way: \(newMessage)")
    }

    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> {
        try? await Task.sleep(nanoseconds: 500_000_000)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fallo" {
            return .failure(.rateLimited)
        }
        return .success(Self.sampleAudio())
    }

    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Study "notes -> flashcards" call (its schema has a `cards` property). A prompt
        // containing "fallo" exercises the failure path.
        if let properties = schema?["properties"] as? [String: Any], properties["cards"] != nil {
            if prompt.lowercased().contains("fallo") { return .failure(.rateLimited) }
            return .success(#"{"title":"Stub deck","cards":[{"front":"Front 1","back":"Back 1"},{"front":"Front 2","back":"Back 2"},{"front":"Front 3","back":"Back 3"}]}"#)
        }
        // Assistant chat (schema-less; reply text, then an optional `---ACTIONS---` JSON array). The transcript's
        // last `USER:` block decides: "add words" proposes a write, "list words" a read, anything else echoes.
        if schema == nil, systemInstruction.contains("---ACTIONS---") {
            let tail = (prompt.components(separatedBy: "\nUSER: ").last ?? prompt)
                .components(separatedBy: "\n\nWrite the next").first ?? prompt
            let lowered = tail.lowercased()
            if lowered.contains("fallo") { return .failure(.rateLimited) }
            if tail.contains("\n  [") {
                if tail.contains("[read library.words") { return .success("You have some words in your library.") }
                if tail.contains("declined by the user") { return .success("Okay, I won't change anything.") }
                return .success("All done.")
            }
            if lowered.contains("add words") {
                return .success("I'll add two words.\n---ACTIONS---\n[{\"capability\":\"words.add\",\"args\":{\"words\":[\"alpha\",\"beta\"]}}]")
            }
            if lowered.contains("list words") {
                return .success("Let me look.\n---ACTIONS---\n[{\"capability\":\"library.words\",\"args\":{\"limit\":5}}]")
            }
            let echo = tail.components(separatedBy: "\n").first.map { String($0.prefix(60)) } ?? ""
            return .success("Think of \"\(echo)\" this way.")
        }
        // Artifact generation (schema-less, delimited envelope). `fallo` exercises the failure path;
        // an update prompt carries the current payload and gets one extra text block back.
        if schema == nil, systemInstruction.contains("---PAYLOAD---") {
            if prompt.lowercased().contains("fallo") { return .failure(.rateLimited) }
            let isUpdate = prompt.contains("CURRENT PAYLOAD:")
            // An app request ("practice app"), or an update whose current payload is the stub app.
            if prompt.lowercased().contains("practice app") || (isUpdate && prompt.contains("stub app")) {
                let heading = isUpdate ? "<h1>Stub app updated</h1>" : ""
                let html = "<html><body>\(heading)<div id=\"out\">stub app</div><script>palabra.call(\"library.words\",{limit:5}).then(function(w){document.getElementById(\"out\").textContent=\"words:\"+w.length},function(e){document.getElementById(\"out\").textContent=\"error:\"+e.code})</script></body></html>"
                return .success(#"{"kind":"app","title":"Stub app","requests":["library.words","storage.get"]}"# + "\n---PAYLOAD---\n\(html)\n---END---")
            }
            let extra = isUpdate ? #",{"type":"text","text":"Updated"}"# : ""
            let header = #"{"kind":"spec","title":"Stub artifact","requests":["library.words"]}"#
            let blocks = #"{"type":"heading","level":1,"text":"Stub artifact"},{"type":"list","ordered":false,"items":["Same","Same"]},{"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{"limit":10}}},{"type":"checklist","id":"c1","items":["First step","Second step"]}"#
            return .success("\(header)\n---PAYLOAD---\n{\"blocks\":[\(blocks)\(extra)]}\n---END---")
        }
        return .success("{}")
    }

    /// Deterministic: even-indexed words go to "Daily life", odd to "Work", with a tag from the part of speech.
    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> {
        try? await Task.sleep(nanoseconds: 400_000_000)
        if words.contains(where: { $0.word.lowercased() == "fallo" }) { return .failure(.rateLimited) }
        let entries = words.enumerated().map { index, w in
            OrganizerBatchResult.Entry(word: w.word, category: index % 2 == 0 ? "Daily life" : "Work", tags: [w.partOfSpeech.isEmpty ? "general" : w.partOfSpeech.lowercased(), "sample"])
        }
        return .success(OrganizerBatchResult(entries: entries))
    }

    /// A short, quiet sine-wave tone — enough for previews and UI tests to
    /// exercise real `AVAudioPlayer` playback without a network call.
    static func sampleAudio(sampleRate: Int = 24000, duration: Double = 0.3, frequency: Double = 440) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)
        for n in 0..<sampleCount {
            let t = Double(n) / Double(sampleRate)
            let amplitude = 0.2 * sin(2 * Double.pi * frequency * t)
            let sample = Int16(amplitude * Double(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        return WAVAudio.wav(fromPCM: pcm, sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
    }

    static func sampleContent(for input: String, language: SupportedLanguage = .english) -> WordContent {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = word.isEmpty ? "palabra" : word
        return WordContent(
            word: display,
            examples: [
                .init(context: "At school", spanish: "Usamos \"\(display)\" en clase todos los días.", english: "We use \"\(display)\" in class every day."),
                .init(context: "With friends", spanish: "Mi amigo dijo \"\(display)\" ayer.", english: "My friend said \"\(display)\" yesterday."),
                .init(context: "At home", spanish: "Mi familia usa \"\(display)\" en casa.", english: "My family uses \"\(display)\" at home.")
            ],
            meaning: .init(translations: ["(sample translation)"], explanation: "Placeholder content from the stub AI client, used for previews and UI tests."),
            usage: .init(explanation: "Sample usage explanation.", register: "neutral", nuance: nil),
            forms: .init(partOfSpeech: "noun", groups: [.init(label: "Singular / Plural", items: [.init(form: display, note: nil)])]),
            similarWords: [.init(word: "ejemplo", difference: "A generic related word shown for previews.")],
            contentLanguage: language
        )
    }
}
