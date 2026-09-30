import XCTest
@testable import Palabra

@MainActor
final class ResilientAIClientTests: XCTestCase {
    private let ok: Result<[AIModel], AIError> = .success([AIModel(id: "models/m", displayName: "M", description: nil, inputTokenLimit: nil, outputTokenLimit: nil)])

    private func make(
        _ script: [Result<[AIModel], AIError>],
        fallback: String? = nil,
        policy: RetryPolicy = RetryPolicy(),
        interactive: Bool = true,
        online: Bool = true
    ) -> (ResilientAIClient, ScriptedAIClient, ResilienceCenter, SleepRecorder) {
        let base = ScriptedAIClient(script)
        let center = ResilienceCenter()
        let slept = SleepRecorder()
        let client = ResilientAIClient(
            base: base,
            center: center,
            fallbackKey: { fallback },
            policy: { policy },
            connectivity: InstantConnectivity(comesBack: online),
            sleep: { slept.add($0) },
            interactive: interactive
        )
        return (client, base, center, slept)
    }

    /// Answers the person's question as soon as it appears.
    private func answer(_ choice: RetryDecision, on center: ResilienceCenter) -> Task<Void, Never> {
        Task { @MainActor in
            for _ in 0..<500 {
                if center.pendingDecision != nil { center.answer(choice); return }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    // MARK: success and pass-through

    func testSuccessIsPassedThroughUntouched() async {
        let (client, base, _, slept) = make([ok])
        let result = await client.listModels(apiKey: "main")
        XCTAssertEqual(try? result.get().count, 1)
        XCTAssertEqual(base.keysUsed, ["main"])
        XCTAssertEqual(slept.seconds, 0)
    }

    func testDisabledRetryBehavesLikeThePlainClient() async {
        var policy = RetryPolicy(); policy.autoRetryEnabled = false
        let (client, base, _, _) = make([.failure(.serverError(500))], policy: policy)
        let result = await client.listModels(apiKey: "main")
        XCTAssertEqual(result.failureError, .serverError(500))
        XCTAssertEqual(base.callCount, 1, "no retries when switched off")
    }

    // MARK: automatic retry

    func testTransientFailureIsRetriedAutomaticallyAndSucceeds() async {
        let (client, base, center, slept) = make([.failure(.serverError(503)), .failure(.timeout), ok])
        let result = await client.listModels(apiKey: "main")
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(base.callCount, 3)
        XCTAssertEqual(slept.seconds, 2 + 4, "waits double: 2s then 4s")
        XCTAssertNil(center.retrying, "the retry status is cleared afterwards")
        XCTAssertNil(center.pendingDecision)
    }

    func testOfflineWaitsForTheNetworkWithoutUsingUpTries() async {
        let (client, base, _, slept) = make([.failure(.offline), .failure(.offline), .failure(.offline), .failure(.offline), .failure(.offline), ok])
        let result = await client.listModels(apiKey: "main")
        XCTAssertNotNil(try? result.get(), "five offline failures did not exhaust the three tries")
        XCTAssertEqual(base.callCount, 6)
        XCTAssertEqual(slept.seconds, 0, "no backoff sleep while offline; it waits for connectivity instead")
    }

    // MARK: asking the person

    func testWhenTriesRunOutThePersonIsAskedAndCanStop() async {
        let (client, base, center, _) = make(Array(repeating: .failure(.serverError(500)), count: 10))
        let responder = answer(.stop, on: center)
        let result = await client.listModels(apiKey: "main")
        await responder.value
        XCTAssertEqual(result.failureError, .serverError(500))
        XCTAssertEqual(base.callCount, 4, "1 first try + 3 automatic retries, then it asked")
        XCTAssertEqual(center.log.first?.outcome, "Stopped by you")
    }

    func testRetryNowTriesAgainAndCanSucceed() async {
        let script: [Result<[AIModel], AIError>] = Array(repeating: .failure(.serverError(500)), count: 4) + [ok]
        let (client, base, center, _) = make(script)
        let responder = answer(.retryNow, on: center)
        let result = await client.listModels(apiKey: "main")
        await responder.value
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(base.callCount, 5)
    }

    func testRetryPatientlyWaitsMuchLongerThanNormalRetries() async {
        let script: [Result<[AIModel], AIError>] = Array(repeating: .failure(.serverError(500)), count: 4) + [ok]
        let (client, _, center, slept) = make(script)
        let responder = answer(.retryPatiently, on: center)
        _ = await client.listModels(apiKey: "main")
        await responder.value
        // 2 + 4 + 8 automatic, then the patient wait of 8s (2s x 4).
        XCTAssertEqual(slept.seconds, 2 + 4 + 8 + 8)
    }

    func testBackgroundWorkNeverAsksAndStopsQuietly() async {
        let (client, base, center, _) = make(Array(repeating: .failure(.serverError(500)), count: 10), interactive: false)
        let result = await client.listModels(apiKey: "main")
        XCTAssertEqual(result.failureError, .serverError(500))
        XCTAssertNil(center.pendingDecision, "a silent task must not pop up a question")
        XCTAssertEqual(base.callCount, 4)
        XCTAssertEqual(center.log.count, 1, "but the failure is recorded, not invisible")
    }

    // MARK: fallback key

    func testQuotaSwitchesToTheBackupKeyImmediatelyWithoutWaiting() async {
        let (client, base, center, slept) = make([.failure(.quotaExhausted), ok], fallback: "backup")
        let result = await client.listModels(apiKey: "main")
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(base.keysUsed, ["main", "backup"])
        XCTAssertEqual(slept.seconds, 0, "waiting never fixes a spent quota")
        XCTAssertEqual(center.activeSlot, .fallback)
        XCTAssertNotNil(center.notice)
    }

    func testInvalidMainKeyFallsBackToTheBackup() async {
        let (client, base, _, _) = make([.failure(.invalidAPIKey), ok], fallback: "backup")
        _ = await client.listModels(apiKey: "main")
        XCTAssertEqual(base.keysUsed, ["main", "backup"])
    }

    func testRepeatedRateLimitingFallsBackAfterTheTries() async {
        let script: [Result<[AIModel], AIError>] = Array(repeating: .failure(.rateLimited), count: 4) + [ok]
        let (client, base, _, _) = make(script, fallback: "backup")
        let result = await client.listModels(apiKey: "main")
        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(base.keysUsed, ["main", "main", "main", "main", "backup"])
    }

    func testBenchedMainKeyIsSkippedOnLaterCalls() async {
        let (client, base, _, _) = make([.failure(.quotaExhausted), ok, ok], fallback: "backup")
        _ = await client.listModels(apiKey: "main")
        _ = await client.listModels(apiKey: "main")
        XCTAssertEqual(base.keysUsed, ["main", "backup", "backup"], "the second call goes straight to the working key")
    }

    func testWithoutABackupAQuotaErrorAsksThePerson() async {
        let (client, base, center, _) = make([.failure(.quotaExhausted)])
        let responder = answer(.stop, on: center)
        let result = await client.listModels(apiKey: "main")
        await responder.value
        XCTAssertEqual(result.failureError, .quotaExhausted)
        XCTAssertEqual(base.callCount, 1, "it did not waste time retrying a spent quota")
    }

    func testWhenBackupAlsoFailsThePersonIsAskedAndNothingLoopsForever() async {
        let (client, base, center, _) = make(Array(repeating: .failure(.quotaExhausted), count: 10), fallback: "backup")
        let responder = answer(.stop, on: center)
        let result = await client.listModels(apiKey: "main")
        await responder.value
        XCTAssertEqual(result.failureError, .quotaExhausted)
        XCTAssertEqual(base.keysUsed, ["main", "backup"])
    }

    // MARK: no retry for hopeless errors

    func testBlockedIsNeverRetried() async {
        let (client, base, center, _) = make([.failure(.blocked("SAFETY"))], fallback: "backup")
        let result = await client.listModels(apiKey: "main")
        XCTAssertEqual(result.failureError, .blocked("SAFETY"))
        XCTAssertEqual(base.callCount, 1)
        XCTAssertNil(center.pendingDecision)
    }

    // MARK: center

    func testMultipleWaitingRequestsAllGetTheSameAnswer() async {
        let center = ResilienceCenter()
        let decision = ResilienceCenter.Decision(error: .rateLimited, attempts: 3, canSwitchKey: false, what: "x")
        async let a = center.ask(decision)
        async let b = center.ask(decision)
        try? await Task.sleep(nanoseconds: 50_000_000)
        center.answer(.retryNow)
        let (ra, rb) = await (a, b)
        XCTAssertEqual(ra, .retryNow)
        XCTAssertEqual(rb, .retryNow)
        XCTAssertNil(center.pendingDecision)
    }

    func testLogKeepsOnlyRecentEntriesNewestFirst() {
        let center = ResilienceCenter()
        for i in 0..<(ResilienceCenter.maxLogEntries + 5) { center.record(what: "n\(i)", error: .timeout, outcome: "o") }
        XCTAssertEqual(center.log.count, ResilienceCenter.maxLogEntries)
        XCTAssertEqual(center.log.first?.what, "n\(ResilienceCenter.maxLogEntries + 4)")
    }
}

private extension Result {
    var failureError: Failure? { if case .failure(let e) = self { return e } else { return nil } }
}
