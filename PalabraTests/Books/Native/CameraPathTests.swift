import XCTest
@testable import Palabra

final class CameraPathTests: XCTestCase {
    private func pose(_ x: Double, _ y: Double, _ z: Double, look: Double = 0) -> CameraPose {
        CameraPose(position: SIMD3(x, y, z), look: SIMD3(look, 0, 0))
    }

    private func dist(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    private var openPath: CameraPath {
        // menu -> cover -> reading, the shape of a real open
        CameraPath(poses: [pose(0, 6, 5), pose(0.5, 3.2, 1.7, look: 0.5), pose(0.5, 2.4, 1.1, look: 0.5)], times: [0, 0.55, 1])
    }

    // MARK: path

    func testPathStartsAndEndsExactlyOnItsPoses() {
        let p = openPath
        XCTAssertEqual(p.pose(at: 0), p.start)
        XCTAssertEqual(p.pose(at: 1), p.end)
        XCTAssertEqual(p.pose(at: -3), p.start)
        XCTAssertEqual(p.pose(at: 9), p.end)
    }

    func testPathPassesThroughTheKeyframe() {
        let p = openPath
        let mid = p.pose(at: 0.55)
        XCTAssertEqual(dist(mid.position, p.poses[1].position), 0, accuracy: 1e-9)
        XCTAssertEqual(dist(mid.look, p.poses[1].look), 0, accuracy: 1e-9)
    }

    /// The bug being fixed: speed must not drop to zero at the keyframe (two chained eased tweens stop there).
    func testSpeedDoesNotStallAtTheKeyframe() {
        let p = openPath
        let h = 1e-4
        func speed(_ u: Double) -> Double { dist(p.pose(at: u + h).position, p.pose(at: u - h).position) / (2 * h) }
        let atKey = speed(0.55)
        let nearby = (speed(0.40) + speed(0.70)) / 2
        XCTAssertGreaterThan(atKey, nearby * 0.5, "the camera must keep moving through the cover keyframe")
        // Chained .inOut tweens would have ~0 speed at the join: this is far from it.
        XCTAssertGreaterThan(atKey, 0.5)
    }

    func testPathIsContinuousInPositionAndVelocity() {
        let p = openPath
        var previous = p.pose(at: 0).position
        var previousStep = 0.0
        let n = 2000
        for i in 1...n {
            let position = p.pose(at: Double(i) / Double(n)).position
            let step = dist(position, previous)
            XCTAssertLessThan(step, 0.02, "position jumped at \(i)")
            if i > 2 { XCTAssertLessThan(abs(step - previousStep), 0.004, "velocity jumped at \(i)") }
            previous = position
            previousStep = step
        }
    }

    /// The path itself eases the start and stop (zero end tangents). The camera is driven with linear time, so a tap must not
    /// leave it sitting still: it has to cover a visible part of its route within the first 5% of the time.
    func testStartIsGentleButNotDead() {
        let p = openPath
        let total = (0..<400).reduce(0.0) { $0 + dist(p.pose(at: Double($1 + 1) / 400).position, p.pose(at: Double($1) / 400).position) }
        let first = dist(p.pose(at: 0.05).position, p.start.position) / total
        let last = dist(p.end.position, p.pose(at: 0.95).position) / total
        XCTAssertGreaterThan(first, 0.005, "the camera must start moving at once")
        XCTAssertLessThan(first, 0.05, "but gently")
        XCTAssertLessThan(last, 0.02, "and settle at the end")
    }

    func testDefaultTimesFollowDistance() {
        let short = CameraPath(poses: [pose(0, 0, 0), pose(1, 0, 0), pose(11, 0, 0)])
        XCTAssertEqual(short.times.first, 0)
        XCTAssertEqual(short.times.last, 1)
        // The 10-unit leg gets about ten times the time of the 1-unit leg.
        XCTAssertEqual(short.times[1], 1.0 / 11.0, accuracy: 1e-9)
    }

    func testBadTimesFallBackToDistance() {
        let poses = [pose(0, 0, 0), pose(1, 0, 0), pose(2, 0, 0)]
        XCTAssertEqual(CameraPath(poses: poses, times: [0, 0.9, 0.5]).times, CameraPath(poses: poses).times)
        XCTAssertEqual(CameraPath(poses: poses, times: [0, 1]).times, CameraPath(poses: poses).times)
        XCTAssertEqual(CameraPath(poses: poses, times: [0.1, 0.5, 1]).times, CameraPath(poses: poses).times)
    }

    func testZeroLengthLegDoesNotBreakThePath() {
        let same = pose(1, 1, 1)
        let p = CameraPath(poses: [same, same, pose(2, 2, 2)])
        for i in 0...20 {
            let q = p.pose(at: Double(i) / 20)
            XCTAssertFalse(q.position.x.isNaN || q.position.y.isNaN || q.position.z.isNaN)
        }
        XCTAssertEqual(p.pose(at: 1), p.end)
    }

    func testPathStaysNearItsKeyframes() {
        // A smooth curve may bow a little between keyframes but must not swing wildly (no overshoot past the hull by much).
        let p = openPath
        let ys = (0...200).map { p.pose(at: Double($0) / 200).position.y }
        XCTAssertLessThanOrEqual(ys.max() ?? 0, 6.0 + 0.2)
        XCTAssertGreaterThanOrEqual(ys.min() ?? 0, 2.4 - 0.2)
    }
}
