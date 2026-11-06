import XCTest
@testable import Palabra

final class BookTransitionTests: XCTestCase {
    // MARK: timeline

    func testOpenIsConsistent() {
        let open = BookTransition.open
        XCTAssertTrue(open.isConsistent)
        XCTAssertEqual(open.cameraEnd, open.total, accuracy: 1e-9, "the camera lands with the lid")
        XCTAssertEqual(open.lidEnd, open.total, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(open.bookEnd, open.total)
    }

    func testCloseIsConsistentForAnyNumberOfTurnedLeaves() {
        for turned in [0, 1, 2, 3, 7, 12, 60, 400] {
            let close = BookTransition.close(turnedLeaves: turned)
            XCTAssertTrue(close.isConsistent, "\(turned) leaves")
            XCTAssertEqual(close.cameraEnd, close.total, accuracy: 1e-9, "the camera lands last, with the book (\(turned))")
            XCTAssertLessThanOrEqual(close.lidEnd, close.total + 1e-9)
            XCTAssertLessThanOrEqual(close.bookEnd, close.total + 1e-9)
        }
    }

    /// The bug in the recording: nothing visible happened for the first ~0.9 s of a close. The camera now starts at the tap and the
    /// first leaf turns at once.
    func testCloseStartsMovingAtOnce() {
        for turned in [0, 1, 5, 30] {
            let close = BookTransition.close(turnedLeaves: turned)
            XCTAssertEqual(close.cameraDelay, 0, "camera (\(turned))")
            if turned > 0 { XCTAssertGreaterThan(close.leafDuration, 0) }
        }
    }

    /// The lid starts while the last leaf is still coming down, and the book starts home before the lid is shut.
    func testCloseOverlapsItsParts() {
        let close = BookTransition.close(turnedLeaves: 4)
        let lastLeafEnd = min(0.4, 3 * close.leafStagger) + close.leafDuration
        XCTAssertLessThan(close.lidDelay, lastLeafEnd, "the lid does not wait for the last leaf")
        XCTAssertLessThan(close.bookDelay, close.lidEnd, "the book does not wait for the lid")
    }

    /// Tap to home used to be about 2.3 to 2.6 s; it must now be clearly shorter even for a thick pile of turned leaves.
    func testCloseIsFasterThanTheOldChain() {
        for turned in [1, 3, 7] {
            let old = min(0.5, Double(turned) * 0.05) + 0.45 + 0.9 + 0.9
            XCTAssertLessThan(BookTransition.close(turnedLeaves: turned).total, old - 0.5, "\(turned) leaves")
        }
    }

    func testCloseNeverGrowsWithoutBound() {
        XCTAssertLessThan(BookTransition.close(turnedLeaves: 5000).total, 2.5)
    }

    // MARK: arc

    private func pose(_ x: Double, _ y: Double, _ z: Double) -> CameraPose {
        CameraPose(position: SIMD3(x, y, z), look: SIMD3(x, 0, 0))
    }

    private func dist(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    func testArcStartsAndEndsOnItsPoses() {
        let a = pose(0, 9.9, 6.6), b = pose(-0.5, 3.6, 2.2), over = pose(-0.5, 5, 2.5)
        let path = CameraPath.arc(from: a, to: b, over: over)
        XCTAssertEqual(path.pose(at: 0), a)
        XCTAssertEqual(path.pose(at: 1), b)
    }

    /// The point of the arc: the speed through the middle stays even. With the old `menu -> cover -> reading` stop the peak was
    /// about twice the average and the second leg crawled.
    func testArcSpeedStaysEven() {
        let a = pose(0, 9.9, 6.6), b = pose(-0.5, 3.6, 2.2), over = pose(-0.5, 5.06, 2.53)
        let path = CameraPath.arc(from: a, to: b, over: over)
        let n = 400
        var steps: [Double] = []
        var last = path.pose(at: 0).position
        for i in 1...n {
            let p = path.pose(at: Double(i) / Double(n)).position
            steps.append(dist(p, last))
            last = p
        }
        let mean = steps.reduce(0, +) / Double(n)
        XCTAssertLessThan(steps.max() ?? 0, mean * 1.6, "no slam")
        // After the peak the camera does not crawl: the middle 60% never drops below a third of the average.
        let middle = steps[(n / 5)..<(n * 4 / 5)]
        XCTAssertGreaterThan(middle.min() ?? 0, mean * 0.33, "no crawl")
    }

    func testArcLeansTowardTheBookWithoutStoppingAtIt() {
        let a = pose(0, 10, 7), b = pose(-0.5, 3.6, 2.2), over = pose(-0.5, 5, 2.5)
        let arc = CameraPath.arc(from: a, to: b, over: over, along: 0.6, lean: 0.25)
        // Nearer to the cover pose than the straight line is, at the waypoint's share of the move, but not on it.
        let mid = arc.poses[1].position
        let line = a.position + (b.position - a.position) * 0.6
        XCTAssertLessThan(dist(mid, over.position), dist(line, over.position))
        XCTAssertGreaterThan(dist(mid, over.position), 0.01)
    }

    func testArcWithCoincidentPosesDoesNotProduceNaN() {
        let a = pose(1, 2, 3)
        let path = CameraPath.arc(from: a, to: a, over: a)
        for i in 0...10 {
            let p = path.pose(at: Double(i) / 10).position
            XCTAssertFalse(p.x.isNaN || p.y.isNaN || p.z.isNaN)
        }
    }

    func testArcClampsTheWaypoint() {
        let a = pose(0, 10, 7), b = pose(0, 3, 2), over = pose(0, 5, 3)
        XCTAssertNoThrow(CameraPath.arc(from: a, to: b, over: over, along: 5).pose(at: 0.5))
        XCTAssertNoThrow(CameraPath.arc(from: a, to: b, over: over, along: -5).pose(at: 0.5))
    }
}
