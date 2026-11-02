import Foundation

/// How far the reader may zoom the view. Outside these limits a pinch stretches a little (`rubberBanded`) and relaxes on release.
struct ZoomLimits: Equatable {
    var minZoom: Double
    var maxZoom: Double

    init(_ minZoom: Double, _ maxZoom: Double) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }

    static let reading = ZoomLimits(0.55, 3)
    static let menu = ZoomLimits(0.55, 2.5)
    /// A pinch may stretch this far past a limit (10%), never more.
    static let stretch = 0.1
}

/// Where the content may sit: at least `keepVisibleFraction` of it (per axis) stays inside the view.
struct PanBounds: Equatable {
    /// Half size of the content at zoom 1, in the same units as the pan.
    var extent: SIMD2<Double>
    /// Half size of the view in those units.
    var view: SIMD2<Double> = SIMD2<Double>(1, 1)
    var keepVisibleFraction = 0.3

    /// The allowed pan range on one axis at the given zoom.
    func range(axis: Int, zoom: Double) -> ClosedRange<Double> {
        let e = extent[axis] * zoom
        let v = view[axis]
        let need = keepVisibleFraction * min(2 * e, 2 * v)
        return (-v + need - e)...(v - need + e)
    }

    func clamp(_ pan: SIMD2<Double>, zoom: Double) -> SIMD2<Double> {
        let x = range(axis: 0, zoom: zoom)
        let y = range(axis: 1, zoom: zoom)
        return SIMD2<Double>(BookMath.clamp(pan.x, x.lowerBound, x.upperBound), BookMath.clamp(pan.y, y.lowerBound, y.upperBound))
    }
}

/// The reader's own view change on top of the framed camera pose: a zoom and a pan.
///
/// Screen points `s` (relative to the view centre) map to content points `c = (s - pan) / zoom`, so a pinch keeps the content
/// point under the fingers fixed by moving the pan: `pan' = focus - (focus - pan) * zoom'/zoom`.
struct FreeView: Equatable {
    private(set) var zoom: Double = 1
    var pan: SIMD2<Double> = .zero
    /// The zoom the fingers asked for, before the rubber band; `settle` brings `zoom` back inside the limits.
    private var rawZoom: Double = 1

    var isMoved: Bool {
        abs(zoom - 1) > 1e-6 || abs(pan.x) > 1e-6 || abs(pan.y) > 1e-6
    }

    /// Multiplies the zoom by `scale` (the change since the last call) around `focus`.
    mutating func pinch(scale: Double, focus: SIMD2<Double>, limits: ZoomLimits) {
        guard scale.isFinite, scale > 0 else { return }
        rawZoom = BookMath.clamp(rawZoom * scale, 0.05, 50)
        apply(zoom: Self.rubberBanded(rawZoom, limits), focus: focus)
    }

    /// Releases the pinch: the zoom relaxes into the limits, again around `focus`.
    mutating func settle(limits: ZoomLimits, focus: SIMD2<Double>) {
        rawZoom = BookMath.clamp(rawZoom, limits.minZoom, limits.maxZoom)
        apply(zoom: rawZoom, focus: focus)
    }

    mutating func drag(by delta: SIMD2<Double>, bounds: PanBounds) {
        pan = bounds.clamp(pan + delta, zoom: zoom)
    }

    mutating func clampPan(_ bounds: PanBounds) {
        pan = bounds.clamp(pan, zoom: zoom)
    }

    mutating func reset() {
        self = FreeView()
    }

    private mutating func apply(zoom newZoom: Double, focus: SIMD2<Double>) {
        let ratio = newZoom / zoom
        pan = focus - (focus - pan) * ratio
        zoom = newZoom
    }

    /// Identity inside the limits; beyond them the zoom is squeezed (in log space) towards 10% past the limit and never reaches it.
    static func rubberBanded(_ z: Double, _ limits: ZoomLimits) -> Double {
        let band = log(1 + ZoomLimits.stretch)
        let x = log(z)
        let lo = log(limits.minZoom)
        let hi = log(limits.maxZoom)
        if x > hi { return exp(hi + band * (1 - exp(-(x - hi) / band))) }
        if x < lo { return exp(lo - band * (1 - exp(-(lo - x) / band))) }
        return z
    }

    func rubberBanded(_ z: Double, _ limits: ZoomLimits) -> Double {
        Self.rubberBanded(z, limits)
    }
}

/// Glide after a finger lifts: the velocity decays exponentially.
struct Inertia: Equatable {
    private(set) var velocity: SIMD2<Double>
    /// Per second; about the feel of a scroll view.
    static let decayRate = 3.2
    /// Below this speed (units per second) the glide stops.
    static let stopSpeed = 0.02

    init(velocity: SIMD2<Double>) {
        self.velocity = velocity
    }

    /// The distance to move for this frame, or nil once the glide has ended.
    mutating func step(dt: Double) -> SIMD2<Double>? {
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        if speed < Self.stopSpeed { return nil }
        let decay = exp(-Self.decayRate * dt)
        // Integral of v0 * e^(-k t) over the frame, so the distance does not depend on the frame rate.
        let distance = velocity * ((1 - decay) / Self.decayRate)
        velocity *= decay
        return distance
    }
}

/// Critically damped follow (the usual "smooth damp"): the value chases its target without overshooting. A `smoothTime` of 0
/// (Reduce Motion) jumps straight to the target.
struct SmoothDamp: Equatable {
    private(set) var velocity: Double = 0

    mutating func step(current: Double, target: Double, dt: Double, smoothTime: Double = 0.18) -> Double {
        if smoothTime <= 0 {
            velocity = 0
            return target
        }
        if dt <= 0 { return current }
        let omega = 2 / smoothTime
        let x = omega * dt
        let falloff = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * falloff
        var output = target + (change + temp) * falloff
        if (target - current > 0) == (output > target) {
            output = target
            velocity = 0
        }
        return output
    }

    mutating func reset() { velocity = 0 }
}
