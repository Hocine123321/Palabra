import Foundation

/// A camera move through several poses as ONE continuous curve.
///
/// Opening a book used to be two camera tweens (menu to cover, then cover to reading) and the second started while the first
/// was still moving, which cancelled it and restarted from zero speed: the camera visibly stalled and lurched. A path passes
/// through its keyframes without stopping, so the speed stays continuous from the first frame to the last.
///
/// Pure value type: no SceneKit, no clock, so the curve is unit-tested.
struct CameraPath: Equatable {
    /// Where the camera is at each keyframe, and when (0...1 of the whole move). `times` is strictly increasing from 0 to 1.
    private(set) var poses: [CameraPose]
    private(set) var times: [Double]

    /// `poses` needs at least two entries. `times` defaults to spacing proportional to the distance travelled, so a long leg
    /// gets more of the move than a short one and the speed stays even.
    init(poses: [CameraPose], times: [Double]? = nil) {
        precondition(poses.count >= 2, "a path needs a start and an end")
        self.poses = poses
        if let times, times.count == poses.count, times.first == 0, times.last == 1,
           zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }) {
            self.times = times
        } else {
            self.times = Self.timesByDistance(poses)
        }
    }

    /// A move from `a` to `b` that leans toward `over` on the way, without stopping there.
    ///
    /// The old open went `menu -> cover -> reading`: the first leg was six units, the second one and a half, so the camera
    /// slammed in and then crept (peak speed twice the average). This one has a single waypoint: the point `along` of the way on
    /// the straight line, drawn `lean` of the distance toward `over`. Its time is its share of the distance travelled, so the
    /// speed stays even through it (peak about 1.3 times the average) and the direction never reverses.
    static func arc(from a: CameraPose, to b: CameraPose, over: CameraPose, along: Double = 0.6, lean: Double = 0.25) -> CameraPath {
        let along = min(0.9, max(0.1, along))
        let straight = CameraPose(
            position: a.position + (b.position - a.position) * along,
            look: a.look + (b.look - a.look) * along
        )
        let mid = CameraPose(
            position: straight.position + (over.position - straight.position) * lean,
            look: straight.look + (over.look - straight.look) * lean
        )
        return CameraPath(poses: [a, mid, b])
    }

    var start: CameraPose { poses[0] }
    var end: CameraPose { poses[poses.count - 1] }

    /// The pose at `u` in 0...1 of the move (already eased: pass the eased progress).
    func pose(at u: Double) -> CameraPose {
        let u = min(1, max(0, u))
        var segment = 0
        while segment < poses.count - 2, u > times[segment + 1] { segment += 1 }
        let t0 = times[segment], t1 = times[segment + 1]
        let local = t1 > t0 ? (u - t0) / (t1 - t0) : 1
        return CameraPose(
            position: spline(\.position, segment: segment, t: local),
            look: spline(\.look, segment: segment, t: local)
        )
    }

    // MARK: Catmull-Rom

    /// A cubic Hermite spline through the keyframes (the Catmull-Rom choice of tangents), so it starts and ends exactly on the
    /// first and last pose and passes through the others. Tangents are scaled by the segment's share of the time, so a short
    /// leg does not overshoot.
    private func spline(_ key: KeyPath<CameraPose, SIMD3<Double>>, segment i: Int, t: Double) -> SIMD3<Double> {
        let p1 = poses[i][keyPath: key], p2 = poses[i + 1][keyPath: key]
        let dt = times[i + 1] - times[i]
        let m1 = tangent(key, at: i) * dt
        let m2 = tangent(key, at: i + 1) * dt
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return p1 * h00 + m1 * h10 + p2 * h01 + m2 * h11
    }

    /// Velocity (per unit of `u`) at keyframe `i`. The first and last are zero: that is what eases the camera in and out, so the
    /// move is driven with linear time (an extra ease on top left the camera sitting still after the tap).
    private func tangent(_ key: KeyPath<CameraPose, SIMD3<Double>>, at i: Int) -> SIMD3<Double> {
        guard i > 0, i < poses.count - 1 else { return .zero }
        let prev = poses[i - 1][keyPath: key], next = poses[i + 1][keyPath: key]
        let span = times[i + 1] - times[i - 1]
        return span > 0 ? (next - prev) / span : .zero
    }

    private static func timesByDistance(_ poses: [CameraPose]) -> [Double] {
        var cumulative = [0.0]
        for (a, b) in zip(poses, poses.dropFirst()) {
            let moved = length(b.position - a.position) + length(b.look - a.look)
            cumulative.append(cumulative[cumulative.count - 1] + max(moved, 1e-6))
        }
        let total = cumulative[cumulative.count - 1]
        return cumulative.map { $0 / total }
    }

    private static func length(_ v: SIMD3<Double>) -> Double { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
}
