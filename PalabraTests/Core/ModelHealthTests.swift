import XCTest
@testable import Palabra

@MainActor
final class ModelHealthTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_644_400)

    private func model(_ name: String) -> AIModel {
        AIModel(id: "models/\(name)", displayName: name.uppercased(), description: nil, inputTokenLimit: nil, outputTokenLimit: nil)
    }

    // MARK: status

    func testNewModelIsUnknown() {
        XCTAssertEqual(ModelHealthStore().status(for: "models/a", now: t0), .unknown)
    }

    func testSuccessMarksWorkingAndFadesAfterSixHours() {
        let store = ModelHealthStore()
        store.recordSuccess("models/a", now: t0)
        XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(60)), .working)
        XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(6 * 3600 + 1)), .unknown)
    }

    func testEachFailureKindHasItsOwnMarkAndPause() {
        let cases: [(AIError, ModelStatus, TimeInterval)] = [
            (.rateLimited, .rateLimited, 60), (.quotaExhausted, .quotaUsed, 3600),
            (.serverError(503), .unstable, 120), (.timeout, .unstable, 120),
            (.modelUnavailable("x"), .unavailable, 24 * 3600),
        ]
        for (error, status, pause) in cases {
            let store = ModelHealthStore()
            store.recordFailure("models/a", error: error, now: t0)
            XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(1)), status, "\(error)")
            XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(pause + 1)), .unknown, "\(error) clears by itself")
        }
    }

    func testFailuresThatAreNotTheModelsFaultAreIgnored() {
        let store = ModelHealthStore()
        store.recordSuccess("models/a", now: t0)
        for error in [AIError.offline, .invalidAPIKey, .permissionDenied, .blocked("x"), .malformedResponse, .missingAPIKey] {
            store.recordFailure("models/a", error: error, now: t0.addingTimeInterval(5))
        }
        XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(10)), .working)
    }

    func testLaterSuccessClearsAnEarlierProblem() {
        let store = ModelHealthStore()
        store.recordFailure("models/a", error: .quotaExhausted, now: t0)
        store.recordSuccess("models/a", now: t0.addingTimeInterval(30))
        XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(31)), .working)
    }

    func testStatusSurvivesARestartAndOldRecordsAreDropped() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "health-\(UUID().uuidString)"))
        let first = ModelHealthStore(defaults: defaults, now: t0)
        first.recordSuccess("models/a", now: t0)
        first.recordFailure("models/b", error: .quotaExhausted, now: t0)
        let second = ModelHealthStore(defaults: defaults, now: t0.addingTimeInterval(60))
        XCTAssertEqual(second.status(for: "models/a", now: t0.addingTimeInterval(60)), .working)
        XCTAssertEqual(second.status(for: "models/b", now: t0.addingTimeInterval(60)), .quotaUsed)
        let later = ModelHealthStore(defaults: defaults, now: t0.addingTimeInterval(8 * 24 * 3600))
        XCTAssertEqual(later.status(for: "models/a", now: t0.addingTimeInterval(8 * 24 * 3600)), .unknown)
    }

    func testChangeHandlerFiresOnlyWhenSomethingChanged() {
        let store = ModelHealthStore()
        let count = Counter()
        store.onChange { count.bump() }
        store.recordFailure("models/a", error: .offline, now: t0)
        XCTAssertEqual(count.value, 0, "an offline error says nothing about the model")
        store.recordSuccess("models/a", now: t0)
        XCTAssertEqual(count.value, 1)
    }

    // MARK: choosing a backup

    func testBackupsSkipLimitedModelsAndPreferTheChosenThenWorkingOnes() {
        let store = ModelHealthStore()
        let all = ["pro", "flash", "lite", "flash-lite", "mine", "worked"].map(model)
        store.recordFailure("models/lite", error: .quotaExhausted, now: t0)
        store.recordSuccess("models/worked", now: t0)
        let ids = BackupModelPicker.candidates(failed: model("pro"), models: all, health: store, preferredID: "models/mine", now: t0.addingTimeInterval(5)).map(\.id)
        XCTAssertEqual(ids, ["models/mine", "models/worked", "models/flash", "models/flash-lite"], "chosen backup, then working, then flash before flash-lite; never the failed or limited ones")
    }

    func testAutomaticBackupsRankFlashThenLiteThenTheRest() {
        let store = ModelHealthStore()
        let all = ["big-pro", "flash-lite", "flash", "other"].map(model)
        let ids = BackupModelPicker.candidates(failed: model("x"), models: all, health: store, preferredID: nil, now: t0).map(\.id)
        XCTAssertEqual(ids, ["models/flash", "models/flash-lite", "models/big-pro", "models/other"])
    }

    func testNoBackupWhenEverythingElseIsLimited() {
        let store = ModelHealthStore()
        store.recordFailure("models/b", error: .rateLimited, now: t0)
        XCTAssertTrue(BackupModelPicker.candidates(failed: model("a"), models: [model("a"), model("b")], health: store, preferredID: nil, now: t0.addingTimeInterval(1)).isEmpty)
    }

    // MARK: testing a model

    func testProbeSendsARealQuestionAndRecordsTheOutcome() async throws {
        let ai = MockAIClient()
        let store = ModelHealthStore()
        ai.generateJSONResult = .success("ok")
        let good = await ModelProbe.test(model("a"), apiKey: "k", using: ai, health: store, now: t0)
        XCTAssertNotNil(try? good.get())
        let call = try XCTUnwrap(ai.generateJSONCalls.first)
        XCTAssertEqual(call.prompt, ModelProbe.prompt)
        XCTAssertEqual(store.status(for: "models/a", now: t0.addingTimeInterval(1)), .working)

        ai.generateJSONResult = .failure(.quotaExhausted)
        let bad = await ModelProbe.test(model("b"), apiKey: "k", using: ai, health: store, now: t0)
        if case .failure(.quotaExhausted) = bad {} else { XCTFail("the error is returned") }
        XCTAssertEqual(store.status(for: "models/b", now: t0.addingTimeInterval(1)), .quotaUsed)
    }

    func testProbeStopsOnlyForTroubleThatIsNotTheModels() {
        for error in [AIError.offline, .invalidAPIKey, .permissionDenied, .missingAPIKey] { XCTAssertTrue(ModelProbe.shouldStop(after: error)) }
        for error in [AIError.rateLimited, .quotaExhausted, .modelUnavailable("x"), .serverError(500), .timeout] { XCTAssertFalse(ModelProbe.shouldStop(after: error)) }
    }

    // MARK: strategy

    func testStrategySwitchesModelBeforeKeyForQuotaAndMissingModels() {
        let policy = RetryPolicy()
        XCTAssertEqual(ErrorStrategy.next(after: .quotaExhausted, failedAttempts: 0, policy: policy, hasFallback: true, hasBackupModel: true), .switchModel)
        XCTAssertEqual(ErrorStrategy.next(after: .quotaExhausted, failedAttempts: 0, policy: policy, hasFallback: true, hasBackupModel: false), .switchKey)
        XCTAssertEqual(ErrorStrategy.next(after: .modelUnavailable("x"), failedAttempts: 0, policy: policy, hasFallback: false, hasBackupModel: true), .switchModel)
        XCTAssertEqual(ErrorStrategy.next(after: .modelUnavailable("x"), failedAttempts: 0, policy: policy, hasFallback: false, hasBackupModel: false), .askUser)
    }

    func testStrategyKeyProblemsStillUseTheBackupKey() {
        let policy = RetryPolicy()
        for error in [AIError.invalidAPIKey, .permissionDenied] {
            XCTAssertEqual(ErrorStrategy.next(after: error, failedAttempts: 0, policy: policy, hasFallback: true, hasBackupModel: true), .switchKey, "another model can't fix a bad key")
        }
    }

    func testStrategyRateLimitGetsOneRetryThenAnotherModel() {
        let policy = RetryPolicy()
        if case .retry = ErrorStrategy.next(after: .rateLimited, failedAttempts: 0, policy: policy, hasFallback: false, hasBackupModel: true) {} else { XCTFail("first failure waits") }
        XCTAssertEqual(ErrorStrategy.next(after: .rateLimited, failedAttempts: 1, policy: policy, hasFallback: false, hasBackupModel: true), .switchModel)
    }

    func testStrategyOutagesTryAnotherModelOnlyAfterTheRetries() {
        let policy = RetryPolicy()
        if case .retry = ErrorStrategy.next(after: .serverError(503), failedAttempts: 0, policy: policy, hasFallback: true, hasBackupModel: true) {} else { XCTFail("retries first") }
        XCTAssertEqual(ErrorStrategy.next(after: .serverError(503), failedAttempts: policy.maxAutomaticAttempts, policy: policy, hasFallback: true, hasBackupModel: true), .switchModel)
    }

    func testStrategyNeverSwitchesModelsForABlockedPrompt() {
        XCTAssertEqual(ErrorStrategy.next(after: .blocked("x"), failedAttempts: 0, policy: RetryPolicy(), hasFallback: true, hasBackupModel: true), .giveUp)
    }

    func testPolicyDecodesOlderSavedSettingsWithModelSwitchingOn() throws {
        let old = Data(#"{"maxAutomaticAttempts":2,"autoRetryEnabled":true}"#.utf8)
        let policy = try JSONDecoder().decode(RetryPolicy.self, from: old)
        XCTAssertTrue(policy.switchModelEnabled)
        XCTAssertNil(policy.backupModelID)
        var changed = policy
        changed.backupModelID = "models/x"
        changed.switchModelEnabled = false
        let round = try JSONDecoder().decode(RetryPolicy.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(round, changed)
    }

    // MARK: the client

    private struct Rig {
        let client: ResilientAIClient
        let ai: ModelScriptedAIClient
        let center: ResilienceCenter
        let health: ModelHealthStore
        let slept: SleepRecorder
    }

    private func rig(policy: RetryPolicy = RetryPolicy(), fallbackKey: String? = nil, interactive: Bool = false, models: [AIModel]? = nil) -> Rig {
        let ai = ModelScriptedAIClient()
        let center = ResilienceCenter()
        let health = ModelHealthStore()
        let slept = SleepRecorder()
        let all = models ?? ["a", "b", "c", "d", "e"].map(model)
        let client = ResilientAIClient(
            base: ai, center: center, fallbackKey: { fallbackKey }, policy: { policy },
            connectivity: InstantConnectivity(), sleep: { slept.add($0) }, interactive: interactive,
            modelHealth: health,
            backupModels: { failed in BackupModelPicker.candidates(failed: failed, models: all, health: health, preferredID: policy.backupModelID) }
        )
        return Rig(client: client, ai: ai, center: center, health: health, slept: slept)
    }

    private func ask(_ rig: Rig, _ name: String = "a") async -> Result<String, AIError> {
        await rig.client.generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "main", model: model(name), temperature: 0)
    }

    func testQuotaOnTheChosenModelIsAnsweredByAnotherModelOnTheSameKey() async {
        let r = rig()
        r.ai.results["models/a"] = .failure(.quotaExhausted)
        let result = await ask(r)
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(r.ai.models, ["models/a", "models/b"])
        XCTAssertEqual(r.ai.keys, ["main", "main"], "no key switch")
        XCTAssertEqual(r.slept.seconds, 0, "a spent quota is never waited out")
        XCTAssertFalse(r.center.health.isBenched(.primary, now: Date()), "the key is fine; only the model was out of quota")
        XCTAssertEqual(r.center.notice?.message, .backupModel("B"))
        XCTAssertEqual(r.health.status(for: "models/a"), .quotaUsed)
        XCTAssertEqual(r.health.status(for: "models/b"), .working)
    }

    func testRateLimitIsRetriedOnceThenAnotherModelAnswers() async {
        let r = rig()
        r.ai.results["models/a"] = .failure(.rateLimited)
        let result = await ask(r)
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(r.ai.models, ["models/a", "models/a", "models/b"])
    }

    func testRemovedModelIsAnsweredByAnotherInsteadOfAskingThePerson() async {
        let r = rig(interactive: true)
        r.ai.results["models/a"] = .failure(.modelUnavailable("a"))
        let result = await ask(r)
        XCTAssertNotNil(try? result.get())
        XCTAssertNil(r.center.pendingDecision)
        XCTAssertEqual(r.ai.models, ["models/a", "models/b"])
    }

    func testSwitchingOffKeepsTheOldBehaviour() async {
        var policy = RetryPolicy(); policy.switchModelEnabled = false
        let r = rig(policy: policy)
        r.ai.results["models/a"] = .failure(.quotaExhausted)
        let result = await ask(r)
        if case .failure(.quotaExhausted) = result {} else { XCTFail("fails as before") }
        XCTAssertEqual(r.ai.models, ["models/a"])
    }

    func testTheChosenBackupModelIsTriedFirst() async {
        var policy = RetryPolicy(); policy.backupModelID = "models/d"
        let r = rig(policy: policy)
        r.ai.results["models/a"] = .failure(.quotaExhausted)
        _ = await ask(r)
        XCTAssertEqual(r.ai.models, ["models/a", "models/d"])
    }

    func testAKnownLimitedModelIsSkippedBeforeTheRequestIsSent() async {
        let r = rig()
        r.health.recordFailure("models/a", error: .quotaExhausted, now: Date())
        let result = await ask(r)
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(r.ai.models, ["models/b"], "the limited model isn't tried first")
        XCTAssertEqual(r.center.notice?.message, .backupModel("B"))
    }

    func testOnlyAFewModelsAreTriedBeforeGivingUp() async {
        let r = rig()
        for name in ["a", "b", "c", "d", "e"] { r.ai.results["models/\(name)"] = .failure(.quotaExhausted) }
        let result = await ask(r)
        if case .failure(.quotaExhausted) = result {} else { XCTFail("gives up in the end") }
        XCTAssertEqual(r.ai.models.count, 1 + ResilientAIClient.maxModelSwitches)
    }

    func testPronunciationIsNeverAnsweredByATextModel() async {
        let r = rig()
        r.ai.results["models/tts"] = .failure(.quotaExhausted)
        _ = await r.client.synthesizeSpeech("hola", apiKey: "main", model: model("tts"))
        XCTAssertEqual(r.ai.models, ["models/tts"])
    }

    func testFailingFastStillLearnsButNeverSwitches() async {
        let r = rig()
        r.ai.results["models/a"] = .failure(.rateLimited)
        let result = await r.client.failingFast().generateJSON(prompt: "p", systemInstruction: "s", schema: nil, apiKey: "main", model: model("a"), temperature: 0)
        if case .failure(.rateLimited) = result {} else { XCTFail("one try") }
        XCTAssertEqual(r.ai.models, ["models/a"])
        XCTAssertEqual(r.health.status(for: "models/a"), .rateLimited)
    }

    func testEveryAnswerTeachesTheHealthStore() async {
        let r = rig()
        _ = await ask(r, "a")
        XCTAssertEqual(r.health.status(for: "models/a"), .working)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
