import Foundation

/// The only file that knows both the library (`Word`) and the artifact side. It turns app data
/// into plain `JSONValue`s so `Features/Artifacts` never sees a model type.
enum CapabilityProviders {
    @MainActor
    static func registry(
        words: WordRepository,
        artifacts: ArtifactRepository,
        review: ReviewRepository? = nil,
        cards: CardRepository? = nil,
        wordQueue: WordQueueRepository? = nil,
        hooks: CapabilityHooks = CapabilityHooks(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        aiGateway: AIGateway = AIGateway(),
        aiLimiter: AIUsageLimiter = AIUsageLimiter()
    ) -> CapabilityRegistry {
        let wordsBox = MainActorBox(words)
        let artifactsBox = MainActorBox(artifacts)
        let reviewBox = MainActorBox(review ?? SwiftDataReviewRepository.inMemory())
        let cardsBox = MainActorBox(cards ?? SwiftDataCardRepository.inMemory())
        let queueBox = MainActorBox(wordQueue ?? SwiftDataWordQueueRepository.inMemory())
        return CapabilityRegistry(
            libraryCapabilities(words: wordsBox)
                + statsCapabilities(words: wordsBox, calendar: calendar, now: now)
                + storageCapabilities(artifacts: artifactsBox, scratch: ScratchStorage())
                + aiCapabilities(gateway: aiGateway, limiter: aiLimiter)
                + reviewCapabilities(words: wordsBox, review: reviewBox, now: now)
                + wordsPackCapabilities(words: wordsBox, queue: queueBox, hooks: hooks)
                + studyPackCapabilities(cards: cardsBox, now: now)
        )
    }
}

/// Side effects a capability asks the app to perform after it wrote something; wired by `AppEnvironment`.
final class CapabilityHooks: @unchecked Sendable {
    /// Words were added to the generation queue: start draining it.
    var wordsQueued: (@MainActor @Sendable () -> Void)?
    /// The AI-output language to queue new words with.
    var language: @MainActor @Sendable () -> SupportedLanguage = { .english }
    init() {}
}

// MARK: - Plumbing

/// Carries a main-actor repository into `@Sendable` handlers; it is only ever touched inside `MainActor.run`.
private final class MainActorBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private func argsObject(_ args: JSONValue) -> Result<[String: JSONValue], CapabilityError> {
    switch args {
    case .object(let object): return .success(object)
    case .null: return .success([:])
    default: return .failure(.badArgs("arguments must be an object"))
    }
}

/// An optional integer argument, clamped. Present but not an integer is `badArgs`.
private func intArg(_ object: [String: JSONValue], _ name: String, default fallback: Int, range: ClosedRange<Int>) -> Result<Int, CapabilityError> {
    guard let raw = object[name], raw != .null else { return .success(fallback) }
    guard let value = raw.intValue else { return .failure(.badArgs("\(name) must be an integer")) }
    return .success(min(max(value, range.lowerBound), range.upperBound))
}

private func dayFormatter(for calendar: Calendar) -> DateFormatter {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let formatter = DateFormatter()
    formatter.calendar = gregorian
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

// MARK: - library.*

@MainActor
private func wordItem(_ word: Word, formatter: ISO8601DateFormatter) -> [String: JSONValue] {
    [
        "id": .string(word.id.uuidString),
        "key": .string(word.key),
        "spanish": .string(word.spanish),
        "translation": .string(word.translation),
        "partOfSpeech": .string(word.partOfSpeech),
        "category": word.category.map { JSONValue.string($0) } ?? .null,
        "tags": .array(word.tags.map { JSONValue.string($0) }),
        "createdAt": .string(formatter.string(from: word.createdAt)),
    ]
}

private func libraryCapabilities(words: MainActorBox<WordRepository>) -> [Capability] {
    let list = Capability(
        name: "library.words",
        kind: .read,
        summary: "Lists the user's saved Spanish words, newest first. No audio or chat history.",
        argsSchema: .object([
            "limit": .string("optional integer 1-500, default 100"),
            "offset": .string("optional integer >= 0, default 0"),
            "category": .string("optional section name to filter by (case-insensitive)"),
            "tag": .string("optional tag to filter by (case-insensitive)"),
        ]),
        returnsSummary: "array of {id, key, spanish, translation, partOfSpeech, category (string or null), tags, createdAt (ISO-8601)}",
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            let limit: Int
            switch intArg(object, "limit", default: 100, range: 1...500) {
            case .success(let value): limit = value
            case .failure(let error): return .failure(error)
            }
            let offset: Int
            switch intArg(object, "offset", default: 0, range: 0...Int(Int32.max)) {
            case .success(let value): offset = value
            case .failure(let error): return .failure(error)
            }
            let category = object["category"]?.stringValue?.lowercased()
            let tag = object["tag"]?.stringValue?.lowercased()
            let items: [JSONValue] = await MainActor.run {
                let formatter = ISO8601DateFormatter()
                let filtered = words.value.allWords()
                    .filter { word in
                        if let category, word.category?.lowercased() != category { return false }
                        if let tag, !word.tags.contains(where: { $0.lowercased() == tag }) { return false }
                        return true
                    }
                    .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.key < $1.key }
                return filtered.dropFirst(offset).prefix(limit).map { JSONValue.object(wordItem($0, formatter: formatter)) }
            }
            return .success(.array(items))
        }
    )

    let single = Capability(
        name: "library.word",
        kind: .read,
        summary: "Returns one saved word with its full explanation (examples, meaning, usage, forms, similar words).",
        argsSchema: .object([
            "id": .string("the word's id (from library.words), or"),
            "key": .string("the word's key (lowercase Spanish headword)"),
        ]),
        returnsSummary: "the library.words fields plus content: {word, examples, meaning, usage, forms, similarWords}",
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            let id = object["id"]?.stringValue
            let key = object["key"]?.stringValue
            guard id != nil || key != nil else { return .failure(.badArgs("id or key is required")) }
            var uuid: UUID?
            if let id {
                guard let parsed = UUID(uuidString: id) else { return .failure(.badArgs("id is not a valid id")) }
                uuid = parsed
            }
            let found: [String: JSONValue]? = await MainActor.run {
                let all = words.value.allWords()
                let word = uuid.flatMap { target in all.first { $0.id == target } }
                    ?? key.flatMap { raw in
                        let normalized = WordKey.identity(raw)
                        return all.first { $0.key == raw || $0.key == normalized }
                    }
                guard let word else { return nil }
                var item = wordItem(word, formatter: ISO8601DateFormatter())
                if let data = try? JSONEncoder().encode(word.content), let content = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    item["content"] = content
                }
                return item
            }
            guard let found else { return .failure(.failed("word not found")) }
            return .success(.object(found))
        }
    )
    return [list, single]
}

// MARK: - stats.*

private func statsCapabilities(words: MainActorBox<WordRepository>, calendar: Calendar, now: @escaping @Sendable () -> Date) -> [Capability] {
    let perDay = Capability(
        name: "stats.wordsPerDay",
        kind: .read,
        summary: "How many words the user added on each of the last N days (zero days included).",
        argsSchema: .object(["days": .string("integer 1-365, default 7")]),
        returnsSummary: "array of {day (yyyy-MM-dd), count}, oldest first, ending today",
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            let days: Int
            switch intArg(object, "days", default: 7, range: 1...365) {
            case .success(let value): days = value
            case .failure(let error): return .failure(error)
            }
            let created: [Date] = await MainActor.run { words.value.allWords().map(\.createdAt) }
            var counts: [Date: Int] = [:]
            for date in created { counts[calendar.startOfDay(for: date), default: 0] += 1 }
            let today = calendar.startOfDay(for: now())
            let formatter = dayFormatter(for: calendar)
            let rows: [JSONValue] = (0..<days).reversed().compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return .object(["day": .string(formatter.string(from: day)), "count": .number(Double(counts[day] ?? 0))])
            }
            return .success(.array(rows))
        }
    )

    let perWeek = Capability(
        name: "stats.wordsPerWeek",
        kind: .read,
        summary: "How many words the user added in each of the last N weeks (zero weeks included).",
        argsSchema: .object(["weeks": .string("integer 1-104, default 8")]),
        returnsSummary: "array of {weekStart (yyyy-MM-dd), count}, oldest first, ending with the current week",
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            let weeks: Int
            switch intArg(object, "weeks", default: 8, range: 1...104) {
            case .success(let value): weeks = value
            case .failure(let error): return .failure(error)
            }
            let created: [Date] = await MainActor.run { words.value.allWords().map(\.createdAt) }
            func weekStart(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date) }
            var counts: [Date: Int] = [:]
            for date in created { counts[weekStart(date), default: 0] += 1 }
            let current = weekStart(now())
            let formatter = dayFormatter(for: calendar)
            let rows: [JSONValue] = (0..<weeks).reversed().compactMap { offset in
                guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) else { return nil }
                return .object(["weekStart": .string(formatter.string(from: start)), "count": .number(Double(counts[start] ?? 0))])
            }
            return .success(.array(rows))
        }
    )
    return [perDay, perWeek]
}

// MARK: - storage.*

/// In-memory stand-in for an artifact's storage: used by previews (dry run) and unsaved drafts, so
/// trying an artifact never writes to the database. Obeys the same limits as the real store.
private final class ScratchStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var buckets: [String: [String: JSONValue]] = [:]

    func get(bucket: String, key: String) -> JSONValue {
        lock.lock(); defer { lock.unlock() }
        return buckets[bucket]?[key] ?? .null
    }

    func set(bucket: String, key: String, value: JSONValue) -> Result<Void, CapabilityError> {
        guard key.count <= ArtifactLimits.maxStateKeyLength else { return .failure(.failed("key too long")) }
        lock.lock(); defer { lock.unlock() }
        var items = buckets[bucket] ?? [:]
        items[key] = value
        let total = items.values.reduce(0) { $0 + $1.jsonString.utf8.count }
        guard total <= ArtifactLimits.maxStateBytes else { return .failure(.failed("storage full")) }
        buckets[bucket] = items
        return .success(())
    }

    func remove(bucket: String, key: String) {
        lock.lock(); defer { lock.unlock() }
        buckets[bucket]?[key] = nil
    }
}

private func storageCapabilities(artifacts: MainActorBox<ArtifactRepository>, scratch: ScratchStorage) -> [Capability] {
    /// Draft and preview sessions use scratch storage (nil here); saved artifacts use the repository.
    func realID(_ session: ArtifactSession) -> UUID? {
        session.dryRun ? nil : session.artifactID
    }
    func bucket(_ session: ArtifactSession) -> String { session.artifactID?.uuidString ?? "draft" }
    func keyArg(_ args: JSONValue) -> Result<(key: String, object: [String: JSONValue]), CapabilityError> {
        guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
        guard let key = object["key"]?.stringValue, !key.isEmpty else { return .failure(.badArgs("key is required")) }
        return .success((key, object))
    }
    func message(_ error: ArtifactStorageError) -> String {
        switch error {
        case .storageFull: return "storage full"
        case .keyTooLong: return "key too long"
        case .payloadTooLarge, .notFound: return "storage error"
        }
    }

    let get = Capability(
        name: "storage.get",
        kind: .local,
        summary: "Reads a value this artifact saved earlier (it survives closing the app). Use this instead of localStorage.",
        argsSchema: .object(["key": .string("string, at most 64 characters")]),
        returnsSummary: "the stored JSON value, or null if nothing is stored",
        handler: { args, session in
            switch keyArg(args) {
            case .failure(let error): return .failure(error)
            case .success(let parsed):
                guard let id = realID(session) else { return .success(scratch.get(bucket: bucket(session), key: parsed.key)) }
                let data = await MainActor.run { artifacts.value.stateValue(artifactID: id, key: parsed.key) }
                guard let data, let text = String(data: data, encoding: .utf8) else { return .success(.null) }
                return .success(JSONValue.parse(text) ?? .null)
            }
        }
    )
    let set = Capability(
        name: "storage.set",
        kind: .local,
        summary: "Saves a JSON value under a key for this artifact only. About 256 KB in total per artifact.",
        argsSchema: .object(["key": .string("string, at most 64 characters"), "value": .string("any JSON value")]),
        returnsSummary: "{}",
        handler: { args, session in
            switch keyArg(args) {
            case .failure(let error): return .failure(error)
            case .success(let parsed):
                guard let value = parsed.object["value"] else { return .failure(.badArgs("value is required")) }
                guard let id = realID(session) else {
                    return scratch.set(bucket: bucket(session), key: parsed.key, value: value).map { .object([:]) }
                }
                let data = Data(value.jsonString.utf8)
                let result = await MainActor.run { artifacts.value.setStateValue(artifactID: id, key: parsed.key, value: data) }
                switch result {
                case .success: return .success(.object([:]))
                case .failure(let error): return .failure(.failed(message(error)))
                }
            }
        }
    )
    let remove = Capability(
        name: "storage.remove",
        kind: .local,
        summary: "Deletes a value this artifact saved.",
        argsSchema: .object(["key": .string("string")]),
        returnsSummary: "{}",
        handler: { args, session in
            switch keyArg(args) {
            case .failure(let error): return .failure(error)
            case .success(let parsed):
                guard let id = realID(session) else {
                    scratch.remove(bucket: bucket(session), key: parsed.key)
                    return .success(.object([:]))
                }
                await MainActor.run { artifacts.value.removeStateValue(artifactID: id, key: parsed.key) }
                return .success(.object([:]))
            }
        }
    )
    return [get, set, remove]
}

// MARK: - AI

private enum AIGenerateLimits {
    static let maxPromptLength = 8_000
    static let defaultTemperature = 0.7
    static let temperatureRange = 0.0...2.0
}

private func aiCapabilities(gateway: AIGateway, limiter: AIUsageLimiter) -> [Capability] {
    let generate = Capability(
        name: "ai.generate",
        kind: .ai,
        summary: "Ask the AI a question or give it a task, using your Google AI key (spends your AI quota).",
        argsSchema: .object([
            "prompt": .string("string, 1-\(AIGenerateLimits.maxPromptLength) characters"),
            "schema": .string("optional JSON schema object; when given the text is JSON of that shape"),
            "temperature": .string("optional number 0-2, default \(AIGenerateLimits.defaultTemperature)"),
        ]),
        returnsSummary: "{text}: the AI's answer as a string",
        handler: { args, session in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            guard let prompt = object["prompt"]?.stringValue, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.badArgs("prompt is required"))
            }
            guard prompt.count <= AIGenerateLimits.maxPromptLength else {
                return .failure(.badArgs("prompt is longer than \(AIGenerateLimits.maxPromptLength) characters"))
            }
            var schema: JSONValue?
            if let raw = object["schema"], raw != .null {
                guard case .object = raw else { return .failure(.badArgs("schema must be an object")) }
                schema = raw
            }
            var temperature = AIGenerateLimits.defaultTemperature
            if let raw = object["temperature"], raw != .null {
                guard let value = raw.doubleValue else { return .failure(.badArgs("temperature must be a number")) }
                temperature = min(max(value, AIGenerateLimits.temperatureRange.lowerBound), AIGenerateLimits.temperatureRange.upperBound)
            }
            // Arguments are valid; only now does the call count against the session's budget.
            guard limiter.allow(sessionID: session.sessionID) else { return .failure(.rateLimited) }
            guard let run = gateway.run else { return .failure(.failed("AI is not available")) }
            switch await run(prompt, schema, temperature) {
            case .success(let text): return .success(.object(["text": .string(text)]))
            case .failure(let error): return .failure(.failed(error.userMessage))
            }
        }
    )
    return [generate]
}

// MARK: - review.*

private let maxReviewWordsPerCall = 50

private func reviewCapabilities(words: MainActorBox<WordRepository>, review: MainActorBox<ReviewRepository>, now: @escaping @Sendable () -> Date) -> [Capability] {
    let flag = Capability(
        name: "review.flag",
        kind: .write,
        summary: "Flags saved words the user struggles with. They get a highlight on their detail page and appear in the Need Review list. Only the user can clear them.",
        argsSchema: .object([
            "words": .string("array of 1-50 {id or key (from library.words), score (optional 0-1 weakness, default 0.5), note (optional, <= 200 chars: why)}"),
        ]),
        returnsSummary: "{flagged: number of words flagged, unresolved: [ids or keys that are not in the library]}",
        dryRunValue: .object(["flagged": .number(0), "unresolved": .array([])]),
        describe: { args in
            let count = args["words"]?.arrayValue?.count ?? 0
            return "Flag \(count) word\(count == 1 ? "" : "s") as needing review"
        },
        handler: { args, session in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            guard let items = object["words"]?.arrayValue, !items.isEmpty else { return .failure(.badArgs("words must be a non-empty array")) }
            guard items.count <= maxReviewWordsPerCall else { return .failure(.badArgs("at most \(maxReviewWordsPerCall) words per call")) }
            struct Request: Sendable { var id: UUID?; var key: String?; var label: String; var score: Double; var note: String }
            var requests: [Request] = []
            for item in items {
                guard let entry = item.objectValue else { return .failure(.badArgs("each word must be an object")) }
                let idString = entry["id"]?.stringValue
                let key = entry["key"]?.stringValue
                guard idString != nil || key != nil else { return .failure(.badArgs("each word needs an id or a key")) }
                var uuid: UUID?
                if let idString {
                    guard let parsed = UUID(uuidString: idString) else { return .failure(.badArgs("id is not a valid id")) }
                    uuid = parsed
                }
                var score = 0.5
                if let raw = entry["score"], raw != .null {
                    guard let value = raw.doubleValue else { return .failure(.badArgs("score must be a number")) }
                    score = value
                }
                requests.append(Request(id: uuid, key: key, label: String((idString ?? key ?? "").prefix(64)), score: score, note: entry["note"]?.stringValue ?? ""))
            }
            let source = session.artifactID
            let moment = now()
            let resolvedRequests = requests
            let outcome: (flagged: Int, unresolved: [String]) = await MainActor.run {
                let all = words.value.allWords()
                var flags: [ReviewFlag] = []
                var positions: [UUID: Int] = [:]
                var unresolved: [String] = []
                for request in resolvedRequests {
                    let match = request.id.flatMap { target in all.first { $0.id == target } }
                        ?? request.key.flatMap { raw in
                            let normalized = WordKey.identity(raw)
                            return all.first { $0.key == normalized }
                        }
                    guard let word = match else { unresolved.append(request.label); continue }
                    // The same word twice in one call is one flag with the higher score.
                    if let index = positions[word.id] {
                        flags[index].score = max(flags[index].score, request.score)
                        flags[index].note = request.note
                    } else {
                        positions[word.id] = flags.count
                        flags.append(ReviewFlag(wordID: word.id, headword: word.spanish, translation: word.translation, score: request.score, note: request.note, sourceArtifactID: source))
                    }
                }
                let applied = review.value.flag(flags, now: moment)
                return (applied, unresolved)
            }
            return .success(.object([
                "flagged": .number(Double(outcome.flagged)),
                "unresolved": .array(outcome.unresolved.map { JSONValue.string($0) }),
            ]))
        }
    )

    let list = Capability(
        name: "review.list",
        kind: .read,
        summary: "Lists the words currently flagged as needing review, weakest first.",
        argsSchema: .object([:]),
        returnsSummary: "array of {wordID, headword, translation, score (0-1), note, flagCount, updatedAt (ISO-8601)}",
        handler: { _, _ in
            let items: [JSONValue] = await MainActor.run {
                let formatter = ISO8601DateFormatter()
                return review.value.openNeeds().map { need in
                    JSONValue.object([
                        "wordID": .string(need.wordID.uuidString),
                        "headword": .string(need.headword),
                        "translation": .string(need.translation),
                        "score": .number(need.score),
                        "note": .string(need.note),
                        "flagCount": .number(Double(need.flagCount)),
                        "updatedAt": .string(formatter.string(from: need.updatedAt)),
                    ])
                }
            }
            return .success(.array(items))
        }
    )
    return [flag, list]
}

// MARK: - words.* (pack)

private let maxWordsAddedPerCall = 20
private let maxWordsPlacedPerCall = 50

private func wordsPackCapabilities(
    words: MainActorBox<WordRepository>,
    queue: MainActorBox<WordQueueRepository>,
    hooks: CapabilityHooks
) -> [Capability] {
    let add = Capability(
        name: "words.add",
        kind: .write,
        summary: "Adds new Spanish words to the user's library. Each word is queued and explained by the AI in the background (examples, meaning, forms), so it appears in the library shortly after. Words already saved or already queued are skipped.",
        argsSchema: .object([
            "words": .string("array of 1-20 Spanish words or short phrases (each 1-80 characters)"),
        ]),
        returnsSummary: "{queued: number queued for generation, alreadyInLibrary: [words], alreadyQueued: [words]}",
        dryRunValue: .object(["queued": .number(0), "alreadyInLibrary": .array([]), "alreadyQueued": .array([])]),
        describe: { args in
            let list = (args["words"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(8).joined(separator: ", ")
            return "Add words: \(list)"
        },
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            guard let items = object["words"]?.arrayValue, !items.isEmpty else { return .failure(.badArgs("words must be a non-empty array")) }
            guard items.count <= maxWordsAddedPerCall else { return .failure(.badArgs("at most \(maxWordsAddedPerCall) words per call")) }
            var cleaned: [String] = []
            for item in items {
                guard let raw = item.stringValue else { return .failure(.badArgs("each word must be a string")) }
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, word.count <= 80 else { return .failure(.badArgs("each word must be 1-80 characters")) }
                cleaned.append(word)
            }
            let resolved = cleaned
            let outcome: (queued: Int, inLibrary: [String], alreadyQueued: [String]) = await MainActor.run {
                let language = hooks.language()
                let queuedKeys = Set(queue.value.allItems().filter { $0.existingWordID == nil }.map { WordKey.identity($0.inputWord) })
                var seen = Set<String>()
                var queued = 0
                var inLibrary: [String] = []
                var alreadyQueued: [String] = []
                for word in resolved {
                    let key = WordKey.identity(word)
                    guard seen.insert(key).inserted else { continue }
                    if words.value.find(key: key) != nil { inLibrary.append(word); continue }
                    if queuedKeys.contains(key) { alreadyQueued.append(word); continue }
                    queue.value.enqueue(inputWord: word, mode: .new, language: language)
                    queued += 1
                }
                if queued > 0 { hooks.wordsQueued?() }
                return (queued, inLibrary, alreadyQueued)
            }
            return .success(.object([
                "queued": .number(Double(outcome.queued)),
                "alreadyInLibrary": .array(outcome.inLibrary.map { JSONValue.string($0) }),
                "alreadyQueued": .array(outcome.alreadyQueued.map { JSONValue.string($0) }),
            ]))
        }
    )

    let place = Capability(
        name: "words.place",
        kind: .write,
        summary: "Sets the section (category) and/or tags of saved words. A category or tags you pass replace the old ones; leave one out to keep it.",
        argsSchema: .object([
            "words": .string("array of 1-50 {id or key (from library.words), category (optional, <= 32 chars), tags (optional array of up to 6 short tags)}"),
        ]),
        returnsSummary: "{updated: number of words changed, unresolved: [ids or keys that are not in the library]}",
        dryRunValue: .object(["updated": .number(0), "unresolved": .array([])]),
        describe: { args in
            let items = args["words"]?.arrayValue ?? []
            let categories = Array(Set(items.compactMap { $0["category"]?.stringValue })).sorted().prefix(4).joined(separator: ", ")
            return "Organize \(items.count) word\(items.count == 1 ? "" : "s")" + (categories.isEmpty ? "" : " into: \(categories)")
        },
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            guard let items = object["words"]?.arrayValue, !items.isEmpty else { return .failure(.badArgs("words must be a non-empty array")) }
            guard items.count <= maxWordsPlacedPerCall else { return .failure(.badArgs("at most \(maxWordsPlacedPerCall) words per call")) }
            struct Request: Sendable { var id: UUID?; var key: String?; var label: String; var category: String?; var tags: [String]? }
            var requests: [Request] = []
            for item in items {
                guard let entry = item.objectValue else { return .failure(.badArgs("each word must be an object")) }
                let idString = entry["id"]?.stringValue
                let key = entry["key"]?.stringValue
                guard idString != nil || key != nil else { return .failure(.badArgs("each word needs an id or a key")) }
                var uuid: UUID?
                if let idString {
                    guard let parsed = UUID(uuidString: idString) else { return .failure(.badArgs("id is not a valid id")) }
                    uuid = parsed
                }
                let category = entry["category"]?.stringValue
                var tags: [String]?
                if let rawTags = entry["tags"], rawTags != .null {
                    guard let array = rawTags.arrayValue else { return .failure(.badArgs("tags must be an array of strings")) }
                    tags = array.compactMap(\.stringValue)
                }
                guard category != nil || tags != nil else { return .failure(.badArgs("each word needs a category or tags")) }
                requests.append(Request(id: uuid, key: key, label: String((idString ?? key ?? "").prefix(64)), category: category, tags: tags))
            }
            let resolvedRequests = requests
            let outcome: (updated: Int, unresolved: [String]) = await MainActor.run {
                let all = words.value.allWords()
                var known = Array(Set(all.compactMap(\.category))).sorted()
                var updated = 0
                var unresolved: [String] = []
                for request in resolvedRequests {
                    let match = request.id.flatMap { target in all.first { $0.id == target } }
                        ?? request.key.flatMap { raw in
                            let normalized = WordKey.identity(raw)
                            return all.first { $0.key == normalized }
                        }
                    guard let word = match else { unresolved.append(request.label); continue }
                    var category = word.category
                    var tags = word.tags
                    if let raw = request.category {
                        let cleaned = LibraryTaxonomy.cleanName(raw)
                        if !cleaned.isEmpty {
                            let canonical = LibraryTaxonomy.canonicalCategory(cleaned, known: known)
                            if !known.contains(canonical) { known.append(canonical) }
                            category = canonical
                        }
                    }
                    if let raw = request.tags { tags = LibraryTaxonomy.cleanTags(raw) }
                    words.value.updatePlacement(id: word.id, category: category, tags: tags)
                    updated += 1
                }
                return (updated, unresolved)
            }
            return .success(.object([
                "updated": .number(Double(outcome.updated)),
                "unresolved": .array(outcome.unresolved.map { JSONValue.string($0) }),
            ]))
        }
    )
    return [add, place]
}

// MARK: - study.* (pack)

private let maxCardsPerCall = 30

private func studyPackCapabilities(cards: MainActorBox<CardRepository>, now: @escaping @Sendable () -> Date) -> [Capability] {
    let decks = Capability(
        name: "study.decks",
        kind: .read,
        summary: "Lists the user's flashcard decks with how many cards are due and new. The Vocabulary deck mirrors the library and is managed automatically.",
        argsSchema: .object([:]),
        returnsSummary: "array of {id, name, kind (\"vocabulary\" or \"user\"), total, due, new}",
        handler: { _, _ in
            let moment = now()
            let items: [JSONValue] = await MainActor.run {
                let counts = cards.value.counts(now: moment)
                return cards.value.decks().map { deck in
                    let c = counts[deck.id] ?? DeckCounts()
                    return JSONValue.object([
                        "id": .string(deck.id.uuidString),
                        "name": .string(deck.name),
                        "kind": .string(deck.kind.rawValue),
                        "total": .number(Double(c.total)),
                        "due": .number(Double(c.due)),
                        "new": .number(Double(c.new)),
                    ])
                }
            }
            return .success(.array(items))
        }
    )

    let addCards = Capability(
        name: "study.addCards",
        kind: .write,
        summary: "Adds flashcards (front and back) to one of the user's own decks, creating the deck when it does not exist. Cards already in the deck are skipped. Cannot change the Vocabulary deck.",
        argsSchema: .object([
            "deck": .string("deck name (1-60 characters); matched ignoring case"),
            "cards": .string("array of 1-30 {front, back} (each <= 300 characters)"),
            "create": .string("optional boolean, default true: create the deck when it is missing"),
        ]),
        returnsSummary: "{deck: name, added: number of new cards, created: whether the deck was just created}",
        dryRunValue: .object(["deck": .string(""), "added": .number(0), "created": .bool(false)]),
        describe: { args in
            let count = args["cards"]?.arrayValue?.count ?? 0
            return "Add \(count) card\(count == 1 ? "" : "s") to the deck \"\(args["deck"]?.stringValue ?? "")\""
        },
        handler: { args, _ in
            guard case .success(let object) = argsObject(args) else { return .failure(.badArgs("arguments must be an object")) }
            guard let rawName = object["deck"]?.stringValue else { return .failure(.badArgs("deck is required")) }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { return .failure(.badArgs("deck must be 1-60 characters")) }
            guard let items = object["cards"]?.arrayValue, !items.isEmpty else { return .failure(.badArgs("cards must be a non-empty array")) }
            guard items.count <= maxCardsPerCall else { return .failure(.badArgs("at most \(maxCardsPerCall) cards per call")) }
            var drafts: [CardDraft] = []
            for item in items {
                guard let entry = item.objectValue, let front = entry["front"]?.stringValue, let back = entry["back"]?.stringValue else {
                    return .failure(.badArgs("each card needs a front and a back"))
                }
                drafts.append(CardDraft(front: String(front.prefix(300)), back: String(back.prefix(300))))
            }
            let create = object["create"]?.boolValue ?? true
            let moment = now()
            let resolvedDrafts = drafts
            let outcome: Result<(deck: String, added: Int, created: Bool), CapabilityError> = await MainActor.run {
                let existing = cards.value.decks().first { $0.name.lowercased() == name.lowercased() }
                if let existing {
                    guard existing.kind == .user else { return .failure(.failed("The Vocabulary deck is managed automatically.")) }
                    return .success((existing.name, cards.value.addCards(toDeck: existing.id, drafts: resolvedDrafts, now: moment), false))
                }
                guard create else { return .failure(.failed("No deck is named \"\(name)\".")) }
                let deck = cards.value.createDeck(name: name, drafts: resolvedDrafts, now: moment)
                let added = cards.value.cards(inDeck: deck.id).count
                return .success((deck.name, added, true))
            }
            switch outcome {
            case .failure(let error): return .failure(error)
            case .success(let result):
                return .success(.object([
                    "deck": .string(result.deck),
                    "added": .number(Double(result.added)),
                    "created": .bool(result.created),
                ]))
            }
        }
    )
    return [decks, addCards]
}
