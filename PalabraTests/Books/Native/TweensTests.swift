import XCTest
@testable import Palabra

final class TweensTests: XCTestCase {
    func testEasesMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        XCTAssertFalse(golden.eases.isEmpty)
        for item in golden.eases {
            let ease = try XCTUnwrap(Ease(rawValue: item.name), "unknown ease \(item.name)")
            XCTAssertEqual(ease.apply(item.t), item.value, accuracy: 1e-9, "\(item.name)(\(item.t))")
        }
    }

    func testDelayHoldsThenRuns() {
        let tweens = Tweens()
        var values: [Double] = []
        tweens.add(duration: 1, delay: 0.5, ease: .linear, onUpdate: { values.append($0) })
        tweens.update(dt: 0.25)
        tweens.update(dt: 0.25)
        // Still waiting after 0.25 s; at exactly 0.5 s the tween starts at progress 0, as in the JS.
        XCTAssertEqual(values, [0])
        tweens.update(dt: 0.25)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[1], 0.25, accuracy: 1e-12)
    }

    func testTimeScaleCollapsesDurations() {
        let tweens = Tweens()
        tweens.timeScale = 0.001
        var done = false
        tweens.add(duration: 1, delay: 0.5, onUpdate: { _ in }, onDone: { done = true })
        tweens.update(dt: 0.05)
        XCTAssertTrue(done)
        XCTAssertFalse(tweens.isActive)
    }

    func testCancelledTweenNeverFiresDone() {
        let tweens = Tweens()
        var updates = 0
        var done = 0
        let tween = tweens.add(duration: 1, onUpdate: { _ in updates += 1 }, onDone: { done += 1 })
        tweens.update(dt: 0.1)
        XCTAssertEqual(updates, 1)
        tweens.cancel(tween)
        tweens.update(dt: 5)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(done, 0)
        XCTAssertFalse(tweens.isActive)
    }

    func testOnDoneFiresOnceAtExactlyOne() {
        let tweens = Tweens()
        var last = -1.0
        var done = 0
        tweens.add(duration: 1, ease: .linear, onUpdate: { last = $0 }, onDone: { done += 1 })
        tweens.update(dt: 0.6)
        XCTAssertEqual(last, 0.6, accuracy: 1e-12)
        XCTAssertEqual(done, 0)
        tweens.update(dt: 0.6)
        XCTAssertEqual(last, 1)
        XCTAssertEqual(done, 1)
        tweens.update(dt: 0.6)
        XCTAssertEqual(done, 1)
        XCTAssertFalse(tweens.isActive)
    }

    func testTweenAddedFromACallbackRunsInTheSamePass() {
        let tweens = Tweens()
        var inner: [Double] = []
        tweens.add(duration: 1, ease: .linear, onUpdate: { _ in }, onDone: {
            tweens.add(duration: 1, ease: .linear, onUpdate: { inner.append($0) })
        })
        tweens.update(dt: 1)
        // The first finished and added the second during the pass; the JS loop (for...of over a growing array) advances it too.
        XCTAssertEqual(inner, [1])
    }

    func testZeroDurationStillFinishes() {
        let tweens = Tweens()
        var done = false
        tweens.add(duration: 0, onUpdate: { _ in }, onDone: { done = true })
        tweens.update(dt: 0.016)
        XCTAssertTrue(done)
    }
}
