import Foundation

/// The only file that knows both the library (`Word`) and the artifact side. It turns app data
/// into plain `JSONValue`s so `Features/Artifacts` never sees a model type.
enum CapabilityProviders {
    @MainActor
    static func registry(
        words: WordRepository,
        artifacts: ArtifactRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> CapabilityRegistry {
        let wordsBox = MainActorBox(words)
        let artifactsBox = MainActorBox(artifacts)
        return CapabilityRegistry(
            libraryCapabilities(words: wordsBox)
                + statsCapabilities(words: wordsBox, calendar: calendar, now: now)
                + storageCapabilities(artifacts: artifactsBox, scratch: ScratchStorage())
        )
    }
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
