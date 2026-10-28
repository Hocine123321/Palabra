import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class ExamAITests: XCTestCase {
    private let library = ExamFixtures.library()

    private func ai(_ reply: Result<String, AIError>, language: SupportedLanguage = .english, sent: @escaping (String, String, [String: Any], Double) -> Void = { _, _, _, _ in }) -> ExamAI {
        ExamAI(generate: { prompt, system, schema, temperature in
            sent(prompt, system, schema, temperature)
            return reply
        }, language: language)
    }

    // MARK: - Fresh items

    func testFreshItemsAreMatchedToWordsByHeadwordAndCleaned() throws {
        let json = """
        {"items":[
          {"word":"Hablar","cloze":"Ella _____ tres idiomas.","clozeAnswer":"habla","clozeEnglish":"She speaks three languages.","translatePrompt":"I talk a lot.","reference":"Hablo mucho."},
          {"word":"comer","cloze":"No hay blank here","clozeAnswer":"come","clozeEnglish":"x","translatePrompt":"","reference":""},
          {"word":"beber","cloze":"_____ y _____ agua","clozeAnswer":"bebo","clozeEnglish":"x","translatePrompt":"I drink water.","reference":"Bebo agua."},
          {"word":"unknown","cloze":"_____ hola","clozeAnswer":"x","clozeEnglish":"x","translatePrompt":"a","reference":"b"}
        ]}
        """
        let result = try ExamAI.parseItems(json, words: library).get()
        let hablar = try XCTUnwrap(library.first { $0.headword == "hablar" })
        let beber = try XCTUnwrap(library.first { $0.headword == "beber" })
        XCTAssertEqual(result[hablar.id]?.cloze, "Ella _____ tres idiomas.")
        XCTAssertEqual(result[hablar.id]?.clozeAnswer, "habla")
        XCTAssertEqual(result[hablar.id]?.reference, "Hablo mucho.")
        XCTAssertNil(library.first { $0.headword == "comer" }.flatMap { result[$0.id] }, "an item with no usable part is dropped")
        XCTAssertNil(result[beber.id]?.cloze, "two blanks cannot be answered with one word")
        XCTAssertEqual(result[beber.id]?.translatePrompt, "I drink water.")
        XCTAssertEqual(result.count, 2, "words that were not asked about are ignored")
    }

    func testFreshItemsRejectAReplyThatIsNotTheExpectedJSON() {
        XCTAssertEqual(ExamAI.parseItems("nonsense", words: library), .failure(.malformedResponse))
        XCTAssertEqual(ExamAI.parseItems("{\"items\":\"x\"}", words: library), .failure(.malformedResponse))
    }

    func testFreshItemsSendOnlyAFewWordsAndTheirMeanings() async {
        var prompt = ""
        var schema: [String: Any] = [:]
        let many = (0..<40).map { ExamFixtures.word("palabra\($0)", ["meaning\($0)"]) }
        let client = ai(.success("{\"items\":[]}")) { sentPrompt, _, sentSchema, _ in
            prompt = sentPrompt
            schema = sentSchema
        }
        _ = await client.freshItems(for: many)
        XCTAssertTrue(prompt.contains("palabra0 = meaning0"))
        XCTAssertTrue(prompt.contains("palabra14"))
        XCTAssertFalse(prompt.contains("palabra15"), "at most \(ExamAILimits.maxWords) words per request")
        XCTAssertNotNil(schema["properties"])
    }

    func testFreshItemsForNoWordsAsksNothing() async {
        var asked = false
        let client = ai(.success("{}")) { _, _, _, _ in asked = true }
        let result = await client.freshItems(for: [])
        XCTAssertEqual(result, .success([:]))
        XCTAssertFalse(asked)
    }

    func testFreshItemsPassTheErrorOn() async {
        let result = await ai(.failure(.rateLimited)).freshItems(for: library)
        XCTAssertEqual(result, .failure(.rateLimited))
    }

    // MARK: - Grading

    func testGradeParsesAndClampsTheScore() {
        let grade = ExamAI.parseGrade(#"{"score":1.4,"corrected":"Hablo mucho.","feedback":"Good."}"#)
        XCTAssertEqual(grade?.score, 1)
        XCTAssertEqual(grade?.corrected, "Hablo mucho.")
        XCTAssertEqual(grade?.feedback, "Good.")
        XCTAssertEqual(ExamAI.parseGrade(#"{"score":-3,"corrected":"","feedback":""}"#)?.score, 0)
        XCTAssertNil(ExamAI.parseGrade(#"{"corrected":"x"}"#))
        XCTAssertNil(ExamAI.parseGrade("hi"))
    }

    func testGradeClipsLongFeedback() {
        let long = String(repeating: "a", count: 2_000)
        let grade = ExamAI.parseGrade(#"{"score":0.5,"corrected":"\#(long)","feedback":"\#(long)"}"#)
        XCTAssertEqual(grade?.feedback.count, ExamAILimits.maxFeedback)
        XCTAssertEqual(grade?.corrected?.count, ExamAILimits.maxSentence)
    }

    func testGradeSendsTheTaskTheModelAnswerAndTheStudentsText() async throws {
        var prompt = ""
        var system = ""
        let client = ai(.success(#"{"score":1,"corrected":"","feedback":"ok"}"#), language: .arabic) { sentPrompt, sentSystem, _, _ in
            prompt = sentPrompt
            system = sentSystem
        }
        let question = ExamQuestion(kind: .translate, wordID: UUID(), headword: "hablar", subject: "I talk a lot.", hint: "hablar", format: .written(reference: "Hablo mucho."))
        let grade = try await client.grade(question: question, answer: "Yo hablo mucho").get()
        XCTAssertEqual(grade.score, 1)
        XCTAssertTrue(prompt.contains("I talk a lot."))
        XCTAssertTrue(prompt.contains("Model answer: Hablo mucho."))
        XCTAssertTrue(prompt.contains("Student's answer: Yo hablo mucho"))
        XCTAssertTrue(system.contains("Arabic"), "feedback is written in the person's AI language")
    }

    func testAnUnreadableGradeIsAnError() async {
        let question = ExamQuestion(kind: .writeSentence, wordID: UUID(), headword: "hablar", subject: "hablar", format: .written(reference: nil))
        let result = await ai(.success("nonsense")).grade(question: question, answer: "hola")
        XCTAssertEqual(result, .failure(.malformedResponse))
    }

    // MARK: - Coach

    func testCoachReportIsParsedAndLimited() {
        let tips = (0..<9).map { #"{"word":"w\#($0)","tip":"t\#($0)"}"# }.joined(separator: ",")
        let report = ExamAI.parseCoach(#"{"summary":"You mix up accents.","tips":[\#(tips)],"focus":"Practice ser and estar."}"#)
        XCTAssertEqual(report?.summary, "You mix up accents.")
        XCTAssertEqual(report?.tips.count, ExamAILimits.maxTips)
        XCTAssertEqual(report?.focus, "Practice ser and estar.")
        XCTAssertNil(ExamAI.parseCoach(#"{"summary":"","tips":[],"focus":""}"#), "an empty report is not a report")
        XCTAssertNil(ExamAI.parseCoach("nope"))
    }

    func testCoachOnlySendsTheMissesAndNothingForAPerfectExam() async throws {
        var prompt = ""
        var calls = 0
        let client = ai(.success(#"{"summary":"Fine.","tips":[],"focus":""}"#)) { sentPrompt, _, _, _ in
            prompt = sentPrompt
            calls += 1
        }
        let right = ExamAnswerRecord(id: UUID(), wordID: UUID(), headword: "comer", kindRaw: "typeSpanish", score: 1, given: "comer", expected: "comer")
        let wrong = ExamAnswerRecord(id: UUID(), wordID: UUID(), headword: "hablar", kindRaw: "typeSpanish", score: 0, given: "hablr", expected: "hablar")
        _ = try await client.coach(records: [right, wrong], percent: 50).get()
        XCTAssertTrue(prompt.contains("hablar"))
        XCTAssertTrue(prompt.contains("hablr"))
        XCTAssertFalse(prompt.contains("comer"))
        XCTAssertTrue(prompt.contains("Score: 50%"))

        let perfect = try await client.coach(records: [right], percent: 100).get()
        XCTAssertEqual(perfect.summary, "")
        XCTAssertEqual(calls, 1, "nothing was missed, so nothing was asked")
    }

    // MARK: - The app's link to it

    func testTheAppOffersTheAIOnlyWithAKeyAndAModel() async throws {
        let keychain = KeychainStore(account: "exam-ai-test-\(UUID().uuidString)")
        defer { keychain.delete() }
        let client = MockAIClient()
        client.generateJSONResult = .success(#"{"score":1,"corrected":"","feedback":"ok"}"#)
        client.listModelsResult = .success([AIModel(id: "models/gemini-2.5-flash", displayName: "Flash", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])
        let container = try ModelContainer(for: Schema([Word.self, WordQueueItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let env = AppEnvironment(
            ai: client,
            repository: SwiftDataWordRepository(context: ModelContext(container), audio: PronunciationFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))),
            catalogue: ModelCatalogue(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            ttsCatalogue: ModelCatalogue(cacheFileName: "TTSModelCatalogue.json", filter: TTSModelFilter.apply, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keychain: keychain,
            settings: SettingsStore(defaults: UserDefaults(suiteName: "exam-ai-\(UUID().uuidString)") ?? .standard),
            wordQueue: SwiftDataWordQueueRepository(context: ModelContext(container))
        )
        XCTAssertNil(env.examAI(), "no key")
        env.saveAPIKey("AIzaSyExampleKey1234")
        XCTAssertNil(env.examAI(), "no model")
        await env.catalogue.refresh(apiKey: "AIzaSyExampleKey1234", using: client)
        env.selectedModelID = "models/gemini-2.5-flash"
        let exam = try XCTUnwrap(env.examAI())
        let question = ExamQuestion(kind: .writeSentence, wordID: UUID(), headword: "hablar", subject: "hablar", format: .written(reference: nil))
        let grade = try await exam.grade(question: question, answer: "Hablo.").get()
        XCTAssertEqual(grade.feedback, "ok")
        XCTAssertEqual(client.generateJSONCalls.count, 1)
        XCTAssertNotNil(client.generateJSONCalls[0].schema, "the exam's reply schema was sent")
    }
}
