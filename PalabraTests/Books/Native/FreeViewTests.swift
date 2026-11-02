import XCTest
@testable import Palabra

final class FreeViewTests: XCTestCase {
    private func world(_ v: FreeView, _ s: SIMD2<Double>) -> SIMD2<Double> { (s - v.pan) / v.zoom }

    func testZoomClampsWithRubberBand() {
        var v = FreeView()
        v.pinch(scale: 5, focus: .zero, limits: .reading)
        XCTAssertGreaterThan(v.zoom, 3)
        XCTAssertLessThan(v.zoom, 3.3)
        v.settle(limits: .reading, focus: .zero)
        XCTAssertEqual(v.zoom, 3, accuracy: 1e-12)

        var small = FreeView()
        small.pinch(scale: 0.01, focus: .zero, limits: .reading)
        XCTAssertLessThan(small.zoom, 0.55)
        XCTAssertGreaterThan(small.zoom, 0.55 / 1.1)
        small.settle(limits: .reading, focus: .zero)
        XCTAssertEqual(small.zoom, 0.55, accuracy: 1e-12)
    }

    func testRubberBandIsIdentityInsideTheLimits() {
        for z in [0.55, 0.8, 1, 2, 3] {
            XCTAssertEqual(FreeView.rubberBanded(z, .reading), z, accuracy: 1e-12)
        }
        XCTAssertEqual(FreeView.rubberBanded(2.5, .menu), 2.5, accuracy: 1e-12)
        XCTAssertLessThan(FreeView.rubberBanded(2.6, .menu), 2.75)
    }

    func testPinchBackInsideTheLimitsFollowsTheFingers() {
        var v = FreeView()
        v.pinch(scale: 5, focus: .zero, limits: .reading)
        v.pinch(scale: 0.5, focus: .zero, limits: .reading)
        XCTAssertEqual(v.zoom, 2.5, accuracy: 1e-12)
    }

    func testFocalPointStaysUnderFingers() {
        let focuses: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(0.7, -0.4), SIMD2(-0.9, 0.2), SIMD2(0.3, 0.8), SIMD2(-0.5, -0.6)]
        for f in focuses {
            var v = FreeView()
            v.pan = SIMD2(0.12, -0.07)
            v.pinch(scale: 1.3, focus: SIMD2(0.1, 0.1), limits: .reading)
            let before = world(v, f)
            v.pinch(scale: 1.7, focus: f, limits: .reading)
            let after = world(v, f)
            XCTAssertEqual(before.x, after.x, accuracy: 1e-12)
            XCTAssertEqual(before.y, after.y, accuracy: 1e-12)
            v.pinch(scale: 0.4, focus: f, limits: .reading)
            let back = world(v, f)
            XCTAssertEqual(before.x, back.x, accuracy: 1e-12)
            XCTAssertEqual(before.y, back.y, accuracy: 1e-12)
        }
    }

    func testSettleKeepsTheFocusPoint() {
        var v = FreeView()
        let f = SIMD2<Double>(0.4, -0.3)
        v.pinch(scale: 5, focus: f, limits: .reading)
        let before = world(v, f)
        v.settle(limits: .reading, focus: f)
        let after = world(v, f)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-12)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-12)
    }

    func testPanClampKeepsThirtyPercentVisible() {
        var v = FreeView()
        v.pinch(scale: 2, focus: .zero, limits: .reading)
        let bounds = PanBounds(extent: SIMD2(0.8, 0.9))
        v.drag(by: SIMD2(100, -100), bounds: bounds)
        let e = SIMD2<Double>(0.8, 0.9) * v.zoom
        // Content left edge may go no further right than where 30% of its width still shows.
        let visibleX = 1 - (v.pan.x - e.x)
        XCTAssertEqual(visibleX, 0.3 * min(2 * e.x, 2), accuracy: 1e-12)
        let visibleY = (v.pan.y + e.y) - (-1)
        XCTAssertEqual(visibleY, 0.3 * min(2 * e.y, 2), accuracy: 1e-12)
        // A small drag inside the range moves exactly.
        var w = FreeView()
        w.drag(by: SIMD2(0.1, -0.05), bounds: bounds)
        XCTAssertEqual(w.pan.x, 0.1, accuracy: 1e-12)
        XCTAssertEqual(w.pan.y, -0.05, accuracy: 1e-12)
    }

    func testPanRangeIsNeverEmpty() {
        let bounds = PanBounds(extent: SIMD2(0.1, 3))
        for zoom in [0.55, 1, 3] {
            for axis in 0..<2 {
                let r = bounds.range(axis: axis, zoom: zoom)
                XCTAssertLessThanOrEqual(r.lowerBound, r.upperBound)
            }
        }
    }

    func testInertiaDecaysToZero() throws {
        var inertia = Inertia(velocity: SIMD2(2, -1))
        var total = SIMD2<Double>.zero
        var steps = 0
        while let d = inertia.step(dt: 1.0 / 60) {
            total += d
            steps += 1
            XCTAssertLessThan(steps, 1000, "the glide never ended")
        }
        XCTAssertGreaterThan(steps, 10)
        // Total distance of an exponential decay: v0 / k.
        XCTAssertEqual(total.x, 2 / Inertia.decayRate, accuracy: 0.01)
        XCTAssertEqual(total.y, -1 / Inertia.decayRate, accuracy: 0.01)
    }

    func testInertiaDistanceDoesNotDependOnFrameRate() {
        func travel(dt: Double) -> Double {
            var inertia = Inertia(velocity: SIMD2(1, 0))
            var total = 0.0
            for _ in 0..<Int(0.5 / dt) { total += inertia.step(dt: dt)?.x ?? 0 }
            return total
        }
        XCTAssertEqual(travel(dt: 1.0 / 60), travel(dt: 1.0 / 120), accuracy: 1e-9)
    }

    func testSlowReleaseDoesNotGlide() {
        var inertia = Inertia(velocity: SIMD2(0.005, 0))
        XCTAssertNil(inertia.step(dt: 1.0 / 60))
    }

    func testResetClearsMoved() {
        var v = FreeView()
        XCTAssertFalse(v.isMoved)
        v.pinch(scale: 1.5, focus: SIMD2(0.2, 0.2), limits: .reading)
        XCTAssertTrue(v.isMoved)
        v.reset()
        XCTAssertFalse(v.isMoved)
        XCTAssertEqual(v.zoom, 1)
        XCTAssertEqual(v.pan, .zero)
        // The rubber band forgets too: the next pinch starts from 1.
        v.pinch(scale: 2, focus: .zero, limits: .reading)
        XCTAssertEqual(v.zoom, 2, accuracy: 1e-12)
    }

    func testInvalidPinchScaleIsIgnored() {
        var v = FreeView()
        v.pinch(scale: 0, focus: .zero, limits: .reading)
        v.pinch(scale: -1, focus: .zero, limits: .reading)
        v.pinch(scale: .nan, focus: .zero, limits: .reading)
        v.pinch(scale: .infinity, focus: .zero, limits: .reading)
        XCTAssertEqual(v, FreeView())
    }

    func testSmoothDampApproachesWithoutOvershoot() {
        var damp = SmoothDamp()
        var value = 0.0
        for _ in 0..<600 {
            value = damp.step(current: value, target: 1, dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(value, 1 + 1e-12)
        }
        XCTAssertEqual(value, 1, accuracy: 1e-3)
    }

    func testReducedMotionPathJumpsToTarget() {
        var damp = SmoothDamp()
        XCTAssertEqual(damp.step(current: 0, target: 7, dt: 1.0 / 60, smoothTime: 0), 7)
    }
}
