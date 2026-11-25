import XCTest
@testable import Palabra

final class SRSMasteryTests: XCTestCase {
    private func state(_ phase: SRSPhase, interval: Double = 0) -> SRSState {
        SRSState(phase: phase, interval: interval, ease: SRSScheduler.startingEase, reps: 1, lapses: 0, due: Date())
    }

    func testNewCardsHaveNoRing() {
        XCTAssertEqual(SRSMastery.fraction(for: state(.new)), 0)
    }

    func testLearningCardsShowASmallArc() {
        XCTAssertEqual(SRSMastery.fraction(for: state(.learning, interval: 1)), 0.12)
    }

    func testReviewCardsGrowWithTheirInterval() {
        XCTAssertEqual(SRSMastery.fraction(for: state(.review, interval: 21)), 1, accuracy: 0.0001)
        XCTAssertEqual(SRSMastery.fraction(for: state(.review, interval: 10.5)), 0.5, accuracy: 0.0001)
    }

    func testReviewArcNeverVanishesOrOverflows() {
        XCTAssertEqual(SRSMastery.fraction(for: state(.review, interval: 1)), 0.2, accuracy: 0.0001)
        XCTAssertEqual(SRSMastery.fraction(for: state(.review, interval: 400)), 1, accuracy: 0.0001)
    }
}
