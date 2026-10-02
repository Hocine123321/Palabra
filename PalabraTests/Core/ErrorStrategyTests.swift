import XCTest
@testable import Palabra

final class ErrorStrategyTests: XCTestCase {
    private let policy = RetryPolicy()

    // MARK: each error gets its own reaction

    func testOfflineWaitsForNetworkInsteadOfCountingAttempts() {
        XCTAssertEqual(ErrorStrategy.next(after: .offline, failedAttempts: 0, policy: policy, hasFallback: true), .waitForNetwork)
        XCTAssertEqual(ErrorStrategy.next(after: .offline, failedAttempts: 9, policy: policy, hasFallback: false), .waitForNetwork)
    }

    func testTransientFailuresRetryWithGrowingWaits() {
        XCTAssertEqual(ErrorStrategy.next(after: .serverError(503), failedAttempts: 0, policy: policy, hasFallback: false), .retry(after: 2))
        XCTAssertEqual(ErrorStrategy.next(after: .serverError(503), failedAttempts: 1, policy: policy, hasFallback: false), .retry(after: 4))
        XCTAssertEqual(ErrorStrategy.next(after: .timeout, failedAttempts: 2, policy: policy, hasFallback: false), .retry(after: 8))
    }

    func testAfterAutomaticTriesTheUserIsAsked() {
        XCTAssertEqual(ErrorStrategy.next(after: .serverError(500), failedAttempts: 3, policy: policy, hasFallback: false), .askUser)
    }

    func testAfterAutomaticTriesTheBackupKeyIsPreferredWhenPresent() {
        XCTAssertEqual(ErrorStrategy.next(after: .rateLimited, failedAttempts: 3, policy: policy, hasFallback: true), .switchKey)
        XCTAssertEqual(ErrorStrategy.next(after: .serverError(500), failedAttempts: 3, policy: policy, hasFallback: true), .switchKey)
    }

    func testMalformedRepliesGetOnlyTwoQuickRetries() {
        XCTAssertEqual(ErrorStrategy.next(after: .malformedResponse, failedAttempts: 1, policy: policy, hasFallback: true), .retry(after: 4))
        XCTAssertEqual(ErrorStrategy.next(after: .malformedResponse, failedAttempts: 2, policy: policy, hasFallback: true), .askUser,
                       "a bad reply is not the key's fault, so the backup key is not used")
    }

    func testQuotaAndBadKeysSwitchImmediatelyOrAskNeverWait() {
        for error in [AIError.quotaExhausted, .invalidAPIKey, .permissionDenied] {
            XCTAssertEqual(ErrorStrategy.next(after: error, failedAttempts: 0, policy: policy, hasFallback: true), .switchKey, "\(error)")
            XCTAssertEqual(ErrorStrategy.next(after: error, failedAttempts: 0, policy: policy, hasFallback: false), .askUser, "\(error)")
        }
    }

    func testBlockedAndSetupProblemsNeverRetry() {
        XCTAssertEqual(ErrorStrategy.next(after: .blocked("SAFETY"), failedAttempts: 0, policy: policy, hasFallback: true), .giveUp)
        XCTAssertEqual(ErrorStrategy.next(after: .missingAPIKey, failedAttempts: 0, policy: policy, hasFallback: true), .giveUp)
        XCTAssertEqual(ErrorStrategy.next(after: .noModelSelected, failedAttempts: 0, policy: policy, hasFallback: true), .giveUp)
        XCTAssertEqual(ErrorStrategy.next(after: .modelUnavailable("models/x"), failedAttempts: 0, policy: policy, hasFallback: true), .askUser)
    }

    func testServerRetryHintIsHonoredButCapped() {
        XCTAssertEqual(ErrorStrategy.next(after: .rateLimited, failedAttempts: 0, policy: policy, hasFallback: false, serverHint: 12), .retry(after: 12))
        XCTAssertEqual(ErrorStrategy.next(after: .rateLimited, failedAttempts: 0, policy: policy, hasFallback: false, serverHint: 500), .retry(after: policy.maxAutomaticWait))
    }

    // MARK: policy

    func testBackoffDoublesAndIsCapped() {
        XCTAssertEqual((0..<5).map { policy.delay(forAttempt: $0) }, [2, 4, 8, 16, 30])
    }

    func testPatientWaitsAreMuchLongerAndCapped() {
        XCTAssertEqual(policy.patientDelay(forAttempt: 0), 8)
        XCTAssertEqual(policy.patientDelay(forAttempt: 1), 16)
        XCTAssertLessThanOrEqual(policy.patientDelay(forAttempt: 20), 300)
        XCTAssertGreaterThan(policy.patientDelay(forAttempt: 0), policy.delay(forAttempt: 0))
    }

    func testPolicyDecodingClampsAbsurdValuesAndToleratesMissingKeys() throws {
        let wild = try JSONDecoder().decode(RetryPolicy.self, from: Data(#"{"maxAutomaticAttempts":999,"baseDelay":0,"maxAutomaticWait":99999}"#.utf8))
        XCTAssertEqual(wild.maxAutomaticAttempts, 6)
        XCTAssertEqual(wild.baseDelay, 0.5)
        XCTAssertEqual(wild.maxAutomaticWait, 120)
        XCTAssertTrue(wild.autoRetryEnabled)
        XCTAssertEqual(try JSONDecoder().decode(RetryPolicy.self, from: Data("{}".utf8)), .default)
    }

    // MARK: error classification from Google's messages

    func testQuotaVersusPerMinuteRateLimit() {
        XCTAssertTrue(GeminiClient.isQuotaExhausted("You exceeded your current quota, please check your plan and billing details."))
        XCTAssertTrue(GeminiClient.isQuotaExhausted("Quota exceeded for metric generate_content_free_tier_requests, limit: 50 per day"))
        XCTAssertFalse(GeminiClient.isQuotaExhausted("Quota exceeded for quota metric ... limit: 10 per minute"))
        XCTAssertFalse(GeminiClient.isQuotaExhausted("Resource has been exhausted (e.g. check quota)."))
        XCTAssertFalse(GeminiClient.isQuotaExhausted(""))
    }

    func testModelNameIsExtractedFromNotFoundMessages() {
        XCTAssertEqual(GeminiClient.modelName(in: "models/gemini-9.9-pro is not found for API version v1beta"), "models/gemini-9.9-pro")
        XCTAssertEqual(GeminiClient.modelName(in: "nothing here"), "")
    }

    func testEveryErrorHasHelpfulGuidance() {
        let all: [AIError] = [.missingAPIKey, .noModelSelected, .modelUnavailable("m"), .offline, .timeout, .invalidAPIKey, .permissionDenied, .rateLimited, .quotaExhausted, .serverError(500), .blocked(nil), .truncated, .malformedResponse, .validationFailed([]), .emptyCatalogue, .unknown(nil, "")]
        for error in all {
            XCTAssertFalse(error.headline.isEmpty)
            XCTAssertFalse(error.shortReason.isEmpty)
            XCTAssertFalse(error.explanation(tried: 2, hasBackupKey: true).isEmpty)
            XCTAssertFalse(error.userMessage.isEmpty)
        }
        XCTAssertFalse(AIError.quotaExhausted.canBenefitFromWaiting, "waiting never refills a spent quota")
        XCTAssertTrue(AIError.serverError(503).canBenefitFromWaiting)
    }

    func testRetryDelayIsParsedFromGoogleDurations() {
        XCTAssertEqual(GeminiClient.parseRetryDelay("34s"), 34)
        XCTAssertEqual(GeminiClient.parseRetryDelay("1.5s"), 1.5)
        XCTAssertNil(GeminiClient.parseRetryDelay("soon"))
        XCTAssertNil(GeminiClient.parseRetryDelay("-3s"))
        XCTAssertNil(GeminiClient.parseRetryDelay("nans"))
        XCTAssertNil(GeminiClient.parseRetryDelay(nil))
    }
}
