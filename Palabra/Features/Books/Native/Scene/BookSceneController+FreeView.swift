import CoreGraphics
import Foundation

/// Free view (spec "Free view"): the reader's own zoom and pan on top of the framed camera. `free` holds what the fingers
/// asked for; `freeShown` is what is drawn, chasing it with a critically damped spring (or exactly, with Reduce Motion).
extension BookSceneController {
    private var smoothTime: Double { config.reducedMotion ? 0 : 0.18 }

    var zoomLimits: ZoomLimits { state.mode == .reading ? .reading : .menu }

    /// Content that may not be pushed out of the view: roughly the framed picture (the book or the page) in points.
    var panBounds: PanBounds {
        let w = Double(camera.size.width) / 2, h = Double(camera.size.height) / 2
        return PanBounds(extent: SIMD2(w * 0.9, h * 0.9 * metricsUsable), view: SIMD2(w, h))
    }

    private var metricsUsable: Double { metrics.usableFraction }

    var canFreeMove: Bool { freeEnabled && (state.mode == .menu || state.mode == .reading) }

    func setFreeViewEnabled(_ on: Bool) {
        freeEnabled = on
        if !on { resetFreeView(animated: false) }
        emit()
    }

    func resetFreeView(animated: Bool) {
        freeInertia = nil
        let wasMoved = free.isMoved
        free.reset()
        if !animated || config.reducedMotion {
            freeShown = (1, .zero)
            freeDamp = (SmoothDamp(), SmoothDamp(), SmoothDamp())
            camera.setFree(zoom: 1, pan: .zero)
        }
        if wasMoved { emit() }
    }

    // MARK: Gestures (points in the view; focus relative to the view centre)

    private func centred(_ point: CGPoint) -> SIMD2<Double> {
        SIMD2(Double(point.x - camera.size.width / 2), Double(point.y - camera.size.height / 2))
    }

    func pinchChanged(scale: Double, at point: CGPoint) {
        guard canFreeMove else { return }
        let wasMoved = free.isMoved
        freeInertia = nil
        free.pinch(scale: scale, focus: centred(point), limits: zoomLimits)
        free.clampPan(panBounds)
        if wasMoved != free.isMoved { emit() }
    }

    func pinchEnded(at point: CGPoint) {
        guard canFreeMove else { return }
        free.settle(limits: zoomLimits, focus: centred(point))
        free.clampPan(panBounds)
        emit()
    }

    func panChanged(by delta: CGSize) {
        guard canFreeMove else { return }
        let wasMoved = free.isMoved
        freeInertia = nil
        free.drag(by: SIMD2(Double(delta.width), Double(delta.height)), bounds: panBounds)
        if wasMoved != free.isMoved { emit() }
    }

    /// `velocity` in points per second.
    func panEnded(velocity: CGSize) {
        guard canFreeMove, !config.reducedMotion else { return }
        freeInertia = Inertia(velocity: SIMD2(Double(velocity.width), Double(velocity.height)))
    }

    /// A double tap puts the camera back on its framed pose, unless it landed on something that reacts to a tap.
    func doubleTapped(at point: CGPoint) {
        guard canFreeMove, free.isMoved else { return }
        if state.mode == .reading, let hit = picker?.pageHit(at: point), let entry = current {
            let spot = CGPoint(x: hit.px, y: hit.py)
            if (pageImage(entry, hit.pageIndex)?.hits ?? []).contains(where: { $0.rect.contains(spot) }) { return }
        }
        resetFreeView(animated: true)
    }

    // MARK: Per frame

    func stepFreeView(dt: Double) {
        if var glide = freeInertia {
            if let move = glide.step(dt: dt) {
                free.drag(by: move, bounds: panBounds)
                freeInertia = glide
            } else {
                freeInertia = nil
            }
        }
        let t = smoothTime
        let zoom = freeDamp.zoom.step(current: freeShown.zoom, target: free.zoom, dt: dt, smoothTime: t)
        let x = freeDamp.x.step(current: freeShown.pan.x, target: free.pan.x, dt: dt, smoothTime: t)
        let y = freeDamp.y.step(current: freeShown.pan.y, target: free.pan.y, dt: dt, smoothTime: t)
        guard zoom != freeShown.zoom || x != freeShown.pan.x || y != freeShown.pan.y else { return }
        freeShown = (zoom, SIMD2(x, y))
        camera.setFree(zoom: zoom, pan: CGSize(width: x, height: y))
    }
}
