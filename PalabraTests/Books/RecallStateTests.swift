import XCTest
@testable import Palabra

final class RecallStateTests: XCTestCase {
    private let page = "lesson/page"
    private var key: String { RecallState.key(pageID: page, scope: "1.p.0") }

    func testNothingIsHiddenWhileTheModeIsOff() {
        let state = RecallState()
        XCTAssertFalse(state.isConcealed(target: .essential, key: key, pageID: page))
    }

    func testTargetsAtOrBelowTheLevelAreHidden() {
        var state = RecallState()
        state.setEnabled(true)
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
        XCTAssertFalse(state.isConcealed(target: .keyFacts, key: key, pageID: page), "essential leaves key facts visible")
        state.setLevel(.keyFacts)
        XCTAssertTrue(state.isConcealed(target: .keyFacts, key: key, pageID: page))
        XCTAssertFalse(state.isConcealed(target: .intensive, key: key, pageID: page))
        state.setLevel(.intensive)
        XCTAssertTrue(state.isConcealed(target: .intensive, key: key, pageID: page))
    }

    func testTappingRevealsAndTappingAgainHides() {
        var state = RecallState()
        state.setEnabled(true)
        state.toggle(key: key, pageID: page)
        XCTAssertFalse(state.isConcealed(target: .essential, key: key, pageID: page))
        state.toggle(key: key, pageID: page)
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
    }

    func testRevealingAPageRevealsAllItsTargetsButNotAnotherPages() {
        var state = RecallState()
        state.setEnabled(true)
        state.revealPage(page)
        XCTAssertFalse(state.isConcealed(target: .essential, key: key, pageID: page))
        let other = RecallState.key(pageID: "lesson/other", scope: "1.p.0")
        XCTAssertTrue(state.isConcealed(target: .essential, key: other, pageID: "lesson/other"))
    }

    func testTappingAfterRevealPageHidesJustThatTarget() {
        var state = RecallState()
        state.setEnabled(true)
        state.revealPage(page)
        state.toggle(key: key, pageID: page)
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
        let sibling = RecallState.key(pageID: page, scope: "1.p.1")
        XCTAssertFalse(state.isConcealed(target: .essential, key: sibling, pageID: page))
    }

    func testHidingThePageAgainConcealsEverything() {
        var state = RecallState()
        state.setEnabled(true)
        state.revealPage(page)
        state.toggle(key: key, pageID: page)
        state.hidePage(page)
        XCTAssertFalse(state.isPageRevealed(page))
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
    }

    func testTurningTheModeOffAndOnStartsHidden() {
        var state = RecallState()
        state.setEnabled(true)
        state.toggle(key: key, pageID: page)
        state.setEnabled(false)
        XCTAssertFalse(state.isConcealed(target: .essential, key: key, pageID: page), "mode off shows the original content")
        state.setEnabled(true)
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
    }

    func testChangingTheLevelHidesRevealedAnswersAgain() {
        var state = RecallState()
        state.setEnabled(true)
        state.revealPage(page)
        state.setLevel(.keyFacts)
        XCTAssertTrue(state.isConcealed(target: .essential, key: key, pageID: page))
    }

    func testSettingTheSameLevelKeepsReveals() {
        var state = RecallState()
        state.setEnabled(true)
        state.toggle(key: key, pageID: page)
        state.setLevel(.essential)
        XCTAssertFalse(state.isConcealed(target: .essential, key: key, pageID: page))
    }
}
