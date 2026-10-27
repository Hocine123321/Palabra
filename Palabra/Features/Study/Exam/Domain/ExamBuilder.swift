import Foundation

/// A small repeatable random generator, so a test can build the same exam twice.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// What the device can do right now (the builder only asks for what works).
struct ExamCapabilities: Equatable, Sendable {
    var speech = false
}

/// Builds the questions of an exam from the library. Pure: no storage, no AI, no clock. Every question is made from the
/// person's own words, examples and forms, so an exam needs no connection; AI-written material only adds to it.
struct ExamBuilder<Generator: RandomNumberGenerator> {
    static var maxOptions: Int { 4 }
    static var matchSize: Int { 4 }

    var rng: Generator
    /// The whole library: wrong answers are drawn from it, not only from the words being tested.
    let pool: [ExamWord]
    let capabilities: ExamCapabilities
    let aiItems: [UUID: ExamAIItem]

    init(rng: Generator, pool: [ExamWord], capabilities: ExamCapabilities = ExamCapabilities(), aiItems: [UUID: ExamAIItem] = [:]) {
        self.rng = rng
        self.pool = pool
        self.capabilities = capabilities
        self.aiItems = aiItems
    }

    // MARK: - Build

    mutating func build(config: ExamConfig, stats: [UUID: ExamWordStat]) -> [ExamQuestion] {
        let kinds = config.kinds
        guard !kinds.isEmpty else { return [] }
        let chosen = select(config.source, count: config.questionCount, stats: stats)
        guard !chosen.isEmpty else { return [] }
        let slots = Self.slots(of: chosen, count: config.questionCount)

        var used: [ExamQuestionKind: Int] = [:]
        var kindsOfWord: [UUID: Set<ExamQuestionKind>] = [:]
        var questions: [ExamQuestion] = []
        let maxMatches = max(1, config.questionCount / 15)

        for word in slots {
            let taken = kindsOfWord[word.id] ?? []
            var options = kinds.filter { !taken.contains($0) && eligible($0, word, chosen: chosen) }
            if used[.matchPairs, default: 0] >= maxMatches { options.removeAll { $0 == .matchPairs } }
            // Variety: the kind used least so far, ties broken at random.
            options = shuffled(options)
            options.sort { used[$0, default: 0] < used[$1, default: 0] }
            for kind in options {
                guard let question = make(kind, for: word, chosen: chosen) else { continue }
                questions.append(question)
                used[kind, default: 0] += 1
                kindsOfWord[word.id, default: []].insert(kind)
                break
            }
        }
        return separateNeighbours(shuffled(questions))
    }

    /// The words an exam of this config will ask about, in order. Build with the same seed afterwards and these are the
    /// words used: the app asks the AI for fresh sentences for exactly these.
    mutating func plannedWords(config: ExamConfig, stats: [UUID: ExamWordStat]) -> [ExamWord] {
        let chosen = select(config.source, count: config.questionCount, stats: stats)
        return Self.slots(of: chosen, count: config.questionCount)
    }

    /// Each word once, then once more if the exam is longer than the list.
    private static func slots(of chosen: [ExamWord], count: Int) -> [ExamWord] {
        var slots = chosen
        if slots.count < count { slots += chosen }
        return Array(slots.prefix(count))
    }

    // MARK: - Choosing words

    private mutating func select(_ source: ExamSource, count: Int, stats: [UUID: ExamWordStat]) -> [ExamWord] {
        let usable = pool.filter { !$0.headword.trimmingCharacters(in: .whitespaces).isEmpty }
        switch source {
        case .all:
            return shuffled(usable)
        case .weakest:
            // Wrong-most first; words never tested count as a little unsure, so they come before the ones you know.
            func weakness(_ word: ExamWord) -> Double {
                guard let stat = stats[word.id], stat.attempts > 0 else { return 0.5 }
                return stat.accuracy
            }
            return shuffled(usable).sorted { weakness($0) < weakness($1) }
        case .recent:
            return Array(usable.sorted { $0.createdAt > $1.createdAt }.prefix(max(count, 1)))
        case .needReview:
            return shuffled(usable.filter(\.needsReview))
        case .section(let name):
            return shuffled(usable.filter { $0.category == name })
        case .tag(let tag):
            return shuffled(usable.filter { word in word.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } })
        case .words(let ids):
            let wanted = Set(ids)
            return shuffled(usable.filter { wanted.contains($0.id) })
        }
    }

    // MARK: - Eligibility

    private func eligible(_ kind: ExamQuestionKind, _ word: ExamWord, chosen: [ExamWord]) -> Bool {
        switch kind {
        case .meaningChoice, .reverseChoice:
            return !word.translations.isEmpty && !wrongTranslations(for: word).isEmpty
        case .similarChoice:
            return !word.similar.isEmpty && !otherHeadwords(than: word, excluding: word.similar.map(\.word)).isEmpty
        case .matchPairs:
            return matchCandidates(chosen).count >= Self.matchSize && matchCandidates(chosen).contains { $0.id == word.id }
        case .typeSpanish, .typeMeaning:
            return !word.translations.isEmpty
        case .fillBlank:
            return clozeSource(for: word) != nil
        case .formChoice:
            return distinctForms(of: word).count >= 2
        case .reorder:
            return reorderExample(for: word) != nil
        case .listening:
            return true
        case .speaking:
            return capabilities.speech && !word.translations.isEmpty
        case .writeSentence:
            return !word.translations.isEmpty
        case .translate:
            return aiItems[word.id]?.translatePrompt != nil && aiItems[word.id]?.reference != nil
        }
    }

    // MARK: - Making questions

    private mutating func make(_ kind: ExamQuestionKind, for word: ExamWord, chosen: [ExamWord]) -> ExamQuestion? {
        switch kind {
        case .meaningChoice: return meaningChoice(word)
        case .reverseChoice: return reverseChoice(word)
        case .similarChoice: return similarChoice(word)
        case .matchPairs: return matchPairs(word, chosen: chosen)
        case .typeSpanish:
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword,
                subject: word.translations.prefix(2).joined(separator: " / "),
                hint: word.partOfSpeech.isEmpty ? nil : word.partOfSpeech,
                format: .typed(accepted: [word.headword], english: false),
                explanation: exampleLine(word)
            )
        case .typeMeaning:
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword, subject: word.headword,
                hint: word.partOfSpeech.isEmpty ? nil : word.partOfSpeech,
                format: .typed(accepted: word.translations, english: true),
                explanation: exampleLine(word)
            )
        case .fillBlank: return fillBlank(word)
        case .formChoice: return formChoice(word)
        case .reorder: return reorder(word)
        case .listening:
            // Mostly the word; sometimes a whole example sentence (dictation).
            let sentences = word.examples.map(\.spanish).filter { (3...9).contains(AnswerMatcher.tokens(of: $0).count) }
            let useSentence = !sentences.isEmpty && Int.random(in: 0..<100, using: &rng) < 30
            let text = useSentence ? (shuffled(sentences).first ?? word.headword) : word.headword
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword, subject: "",
                format: .typed(accepted: [text], english: false),
                explanation: word.primaryTranslation.isEmpty ? nil : word.primaryTranslation,
                speakText: text
            )
        case .speaking:
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword,
                subject: word.translations.prefix(2).joined(separator: " / "),
                hint: word.partOfSpeech.isEmpty ? nil : word.partOfSpeech,
                format: .spoken(target: word.headword),
                explanation: exampleLine(word)
            )
        case .writeSentence:
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword, subject: word.headword,
                hint: word.primaryTranslation.isEmpty ? nil : word.primaryTranslation,
                format: .written(reference: word.examples.first?.spanish),
                explanation: nil
            )
        case .translate:
            guard let item = aiItems[word.id], let prompt = item.translatePrompt, let reference = item.reference else { return nil }
            return ExamQuestion(
                kind: kind, wordID: word.id, headword: word.headword, subject: prompt,
                hint: word.headword, format: .written(reference: reference), explanation: nil
            )
        }
    }

    private mutating func meaningChoice(_ word: ExamWord) -> ExamQuestion? {
        guard let answer = word.translations.first else { return nil }
        let wrong = pickWrong(from: wrongTranslations(for: word), same: word, matching: { $0.primaryTranslation })
        guard !wrong.isEmpty else { return nil }
        let (options, correct) = arranged(answer, wrong)
        return ExamQuestion(
            kind: .meaningChoice, wordID: word.id, headword: word.headword, subject: word.headword,
            hint: word.partOfSpeech.isEmpty ? nil : word.partOfSpeech,
            format: .choice(options: options, correct: correct), explanation: exampleLine(word)
        )
    }

    private mutating func reverseChoice(_ word: ExamWord) -> ExamQuestion? {
        guard let prompt = word.translations.first else { return nil }
        let others = pool.filter { $0.id != word.id && AnswerMatcher.fold($0.headword) != AnswerMatcher.fold(word.headword) }
        let wrong = Array(pickWrongWords(others, like: word).prefix(Self.maxOptions - 1)).map(\.headword)
        guard !wrong.isEmpty else { return nil }
        let (options, correct) = arranged(word.headword, wrong)
        return ExamQuestion(
            kind: .reverseChoice, wordID: word.id, headword: word.headword, subject: prompt,
            hint: word.partOfSpeech.isEmpty ? nil : word.partOfSpeech,
            format: .choice(options: options, correct: correct), explanation: exampleLine(word)
        )
    }

    private mutating func similarChoice(_ word: ExamWord) -> ExamQuestion? {
        guard let similar = shuffled(word.similar).first else { return nil }
        let candidates = otherHeadwords(than: word, excluding: word.similar.map(\.word))
        let wrong = Array(shuffled(candidates).prefix(Self.maxOptions - 1))
        guard !wrong.isEmpty else { return nil }
        let (options, correct) = arranged(similar.word, wrong)
        return ExamQuestion(
            kind: .similarChoice, wordID: word.id, headword: word.headword, subject: word.headword,
            hint: word.primaryTranslation.isEmpty ? nil : word.primaryTranslation,
            format: .choice(options: options, correct: correct),
            explanation: similar.difference.isEmpty ? nil : "\(similar.word): \(similar.difference)"
        )
    }

    private mutating func matchPairs(_ word: ExamWord, chosen: [ExamWord]) -> ExamQuestion? {
        var group = [word]
        for other in shuffled(matchCandidates(chosen)) where other.id != word.id && group.count < Self.matchSize + 1 {
            group.append(other)
        }
        guard group.count >= Self.matchSize else { return nil }
        let pairs = group.map { ExamQuestion.Pair(wordID: $0.id, left: $0.headword, right: $0.primaryTranslation) }
        return ExamQuestion(
            kind: .matchPairs, wordID: word.id, headword: word.headword, subject: "",
            format: .match(pairs: pairs), involvedWordIDs: group.map(\.id)
        )
    }

    private mutating func fillBlank(_ word: ExamWord) -> ExamQuestion? {
        guard let cloze = clozeSource(for: word, picking: true) else { return nil }
        let siblings = distinctForms(of: word).map(\.form).filter { AnswerMatcher.fold($0) != AnswerMatcher.fold(cloze.answer) }
        var wrong = Array(shuffled(siblings).prefix(Self.maxOptions - 1))
        if wrong.count < Self.maxOptions - 1 {
            let extra = pool
                .filter { $0.id != word.id }
                .map(\.headword)
                .filter { AnswerMatcher.fold($0) != AnswerMatcher.fold(cloze.answer) && !wrong.contains($0) }
            wrong += Array(shuffled(extra).prefix(Self.maxOptions - 1 - wrong.count))
        }
        // Mostly pick-one; sometimes type it. Without enough wrong answers it can only be typed.
        let typed = wrong.count < 2 || Int.random(in: 0..<100, using: &rng) < 35
        let format: ExamQuestion.Format
        if typed {
            format = .typed(accepted: [cloze.answer], english: false)
        } else {
            let (options, correct) = arranged(cloze.answer, wrong)
            format = .choice(options: options, correct: correct)
        }
        return ExamQuestion(
            kind: .fillBlank, wordID: word.id, headword: word.headword, subject: cloze.blanked,
            hint: cloze.english.isEmpty ? nil : cloze.english, format: format, explanation: cloze.full
        )
    }

    private mutating func formChoice(_ word: ExamWord) -> ExamQuestion? {
        let forms = distinctForms(of: word)
        guard forms.count >= 2 else { return nil }
        let withNote = forms.filter { $0.note != nil }
        guard let target = shuffled(withNote.isEmpty ? forms : withNote).first else { return nil }
        var wrong = Array(shuffled(forms.filter { AnswerMatcher.fold($0.form) != AnswerMatcher.fold(target.form) }.map(\.form)).prefix(Self.maxOptions - 1))
        if wrong.count < Self.maxOptions - 1 {
            let extra = pool
                .filter { $0.id != word.id && $0.partOfSpeech == word.partOfSpeech }
                .flatMap(\.forms)
                .map(\.form)
                .filter { AnswerMatcher.fold($0) != AnswerMatcher.fold(target.form) && !wrong.contains($0) }
            wrong += Array(shuffled(Array(Set(extra))).prefix(Self.maxOptions - 1 - wrong.count))
        }
        let (options, correct) = arranged(target.form, wrong)
        let hint = [target.label, target.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return ExamQuestion(
            kind: .formChoice, wordID: word.id, headword: word.headword, subject: word.headword,
            hint: hint.isEmpty ? nil : hint, format: .choice(options: options, correct: correct),
            explanation: word.primaryTranslation.isEmpty ? nil : word.primaryTranslation
        )
    }

    private mutating func reorder(_ word: ExamWord) -> ExamQuestion? {
        guard let example = reorderExample(for: word) else { return nil }
        let answer = AnswerMatcher.tokens(of: example.spanish)
        var tokens = shuffled(answer)
        var attempts = 0
        while tokens.map(AnswerMatcher.fold) == answer.map(AnswerMatcher.fold), attempts < 6 {
            tokens = shuffled(answer)
            attempts += 1
        }
        if tokens.map(AnswerMatcher.fold) == answer.map(AnswerMatcher.fold) { tokens = answer.reversed() }
        return ExamQuestion(
            kind: .reorder, wordID: word.id, headword: word.headword, subject: example.english,
            format: .reorder(tokens: tokens, answer: answer), explanation: example.spanish
        )
    }

    // MARK: - Helpers

    /// "hablar: Hablo español. (I speak Spanish.)" shown after an answer.
    private func exampleLine(_ word: ExamWord) -> String? {
        guard let example = word.examples.first else { return nil }
        return example.english.isEmpty ? example.spanish : "\(example.spanish)\n\(example.english)"
    }

    private func distinctForms(of word: ExamWord) -> [ExamWord.Form] {
        var seen = Set<String>()
        return word.forms.filter { !$0.form.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert(AnswerMatcher.fold($0.form)).inserted }
    }

    private func reorderExample(for word: ExamWord) -> ExamWord.Example? {
        word.examples.first {
            let count = AnswerMatcher.tokens(of: $0.spanish).count
            return (3...12).contains(count) && !$0.english.isEmpty
        }
    }

    private struct ClozeMaterial {
        let blanked: String
        let answer: String
        let english: String
        let full: String
    }

    /// A sentence to blank: a fresh AI one if there is one, else an example of the word. With `picking`, the
    /// choice among several is random.
    private func clozeSource(for word: ExamWord) -> ClozeMaterial? {
        var generator = SystemRandomNumberGenerator()
        return clozeSource(for: word, picking: false, using: &generator)
    }

    private mutating func clozeSource(for word: ExamWord, picking: Bool) -> ClozeMaterial? {
        var copy = rng
        let result = clozeSource(for: word, picking: picking, using: &copy)
        rng = copy
        return result
    }

    private func clozeSource<R: RandomNumberGenerator>(for word: ExamWord, picking: Bool, using generator: inout R) -> ClozeMaterial? {
        if let item = aiItems[word.id], let cloze = item.cloze, let answer = item.clozeAnswer,
           cloze.contains(ClozeFinder.blank), !answer.isEmpty {
            return ClozeMaterial(blanked: cloze, answer: answer, english: item.clozeEnglish ?? "", full: cloze.replacingOccurrences(of: ClozeFinder.blank, with: answer))
        }
        let candidates = [word.headword] + word.forms.map(\.form)
        var examples = word.examples
        if picking { examples.shuffle(using: &generator) }
        for example in examples {
            if let cloze = ClozeFinder.make(sentence: example.spanish, candidates: candidates) {
                return ClozeMaterial(blanked: cloze.blanked, answer: cloze.answer, english: example.english, full: cloze.full)
            }
        }
        return nil
    }

    private func matchCandidates(_ chosen: [ExamWord]) -> [ExamWord] {
        var seenHeadwords = Set<String>()
        var seenMeanings = Set<String>()
        return chosen.filter { word in
            let meaning = AnswerMatcher.fold(word.primaryTranslation)
            guard !meaning.isEmpty else { return false }
            return seenHeadwords.insert(AnswerMatcher.fold(word.headword)).inserted && seenMeanings.insert(meaning).inserted
        }
    }

    /// Translations of other words that cannot be mistaken for this word's own.
    private func wrongTranslations(for word: ExamWord) -> [ExamWord] {
        let own = Set(word.translations.map(AnswerMatcher.fold))
        return pool.filter { other in
            guard other.id != word.id, let first = other.translations.first else { return false }
            return !own.contains(AnswerMatcher.fold(first)) && !other.translations.map(AnswerMatcher.fold).contains(AnswerMatcher.fold(word.translations.first ?? ""))
        }
    }

    private func otherHeadwords(than word: ExamWord, excluding: [String]) -> [String] {
        let skip = Set(([word.headword] + excluding).map(AnswerMatcher.fold))
        var seen = Set<String>()
        return pool.map(\.headword).filter { !skip.contains(AnswerMatcher.fold($0)) && seen.insert(AnswerMatcher.fold($0)).inserted }
    }

    /// Wrong answers, preferring words of the same kind (a verb among verbs), and never two the same.
    private mutating func pickWrongWords(_ others: [ExamWord], like word: ExamWord) -> [ExamWord] {
        let same = shuffled(others.filter { $0.partOfSpeech == word.partOfSpeech })
        let different = shuffled(others.filter { $0.partOfSpeech != word.partOfSpeech })
        return same + different
    }

    private mutating func pickWrong(from others: [ExamWord], same word: ExamWord, matching text: (ExamWord) -> String) -> [String] {
        var seen = Set(word.translations.map(AnswerMatcher.fold))
        var result: [String] = []
        for other in pickWrongWords(others, like: word) {
            let value = text(other)
            if seen.insert(AnswerMatcher.fold(value)).inserted { result.append(value) }
            if result.count == Self.maxOptions - 1 { break }
        }
        return result
    }

    /// The answer among the wrong ones, in random order, and where the answer ended up.
    private mutating func arranged(_ answer: String, _ wrong: [String]) -> ([String], Int) {
        let options = shuffled([answer] + wrong)
        return (options, options.firstIndex(of: answer) ?? 0)
    }

    private mutating func shuffled<T>(_ items: [T]) -> [T] {
        var copy = items
        copy.shuffle(using: &rng)
        return copy
    }

    /// No two questions of the same kind in a row, where the list allows it.
    private func separateNeighbours(_ questions: [ExamQuestion]) -> [ExamQuestion] {
        var result = questions
        guard result.count > 2 else { return result }
        for index in 1..<result.count where result[index].kind == result[index - 1].kind {
            if let swap = ((index + 1)..<result.count).first(where: { result[$0].kind != result[index].kind }) {
                result.swapAt(index, swap)
            }
        }
        return result
    }
}

extension ExamBuilder where Generator == SystemRandomNumberGenerator {
    init(pool: [ExamWord], capabilities: ExamCapabilities = ExamCapabilities(), aiItems: [UUID: ExamAIItem] = [:]) {
        self.init(rng: SystemRandomNumberGenerator(), pool: pool, capabilities: capabilities, aiItems: aiItems)
    }
}
