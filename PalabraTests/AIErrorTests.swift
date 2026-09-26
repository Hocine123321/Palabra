import XCTest
@testable import Palabra

final class AIErrorTests: XCTestCase {
    func testInvalidAPIKeyIsNotRetryableAndOpensSettings() {
        XCTAssertFalse(AIError.invalidAPIKey.isRetryable)
        XCTAssertEqual(AIError.invalidAPIKey.recovery, .openSettings)
    }

    func testOfflineIsRetryable() {
        XCTAssertTrue(AIError.offline.isRetryable)
        XCTAssertEqual(AIError.offline.recovery, .retry)
    }

    func testMissingAPIKeyRecoversToSettings() {
        XCTAssertEqual(AIError.missingAPIKey.recovery, .openSettings)
    }

    func testModelUnavailableMessageIncludesID() {
        XCTAssertTrue(AIError.modelUnavailable("models/old-model").userMessage.contains("models/old-model"))
    }

    func testBlockedHasNoRecoveryAction() {
        XCTAssertNil(AIError.blocked("SAFETY").recovery)
    }
}
