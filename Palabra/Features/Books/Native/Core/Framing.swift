import CoreGraphics
import Foundation

/// The screen the camera has to frame, and how much of it the 2D controls cover (`BooksSceneScreen.InsetKey` computes the insets).
struct ViewMetrics: Equatable {
    var size: CGSize
    var insetTop: Double
    var insetBottom: Double
    var fovDegrees: Double = 32

    var aspect: Double { Double(size.width / size.height) }

    /// Landscape: short, so a whole page would be tiny and the reading pose shows about half the width instead.
    var isWide: Bool { aspect > 1.15 }

    /// The share of the height the page may use (what the controls leave free), never below 35%.
    var usableFraction: Double { BookMath.clamp(1 - (insetTop + insetBottom) / Double(size.height), 0.35, 1) }

    /// The camera keeps its view centred in the free area: the view window is moved by this many points.
    var projectionShift: Double { (insetTop - insetBottom) / 2 }
}

struct CameraPose: Equatable {
    var position: SIMD3<Double>
    var look: SIMD3<Double>
}

struct ReadingFrame: Equatable {
    var pose: CameraPose
    /// How far the page can be scrolled up or down in landscape (0 in portrait).
    var panLimit: Double
    /// Screen points per unit of page height at this pose (1 in portrait, where nothing scrolls).
    var pxPerZ: Double
    /// The requested pan, clamped to `panLimit`.
    var pan: Double
}

/// Camera poses of the scene: `_frameRect`, `frameMenu`, the cover pose of `openBook` and `_readTarget` from app.js.
enum Framing {
    private static func radians(_ degrees: Double) -> Double { degrees * (Double.pi / 180) }

    /// Position and look-at that frame a rectangle on a horizontal plane at height `y` (world coordinates).
    static func rect(cx: Double, cz: Double, hw: Double, hh: Double, pitchDegrees: Double, y: Double = 0, _ m: ViewMetrics) -> CameraPose {
        let fov = radians(m.fovDegrees)
        let a = radians(pitchDegrees)
        let tanV = tan(fov / 2)
        let dW = hw / (tanV * m.aspect * 0.98)
        let dH = (hh * sin(a) + 0.12 * cos(a)) / (tanV * m.usableFraction)
        let d = max(dW, dH)
        return CameraPose(
            position: SIMD3<Double>(cx, y + d * sin(a), cz + d * cos(a)),
            look: SIMD3<Double>(cx, y, cz)
        )
    }

    /// Both books on the desk.
    static func menu(_ m: ViewMetrics) -> CameraPose {
        m.isWide
            ? rect(cx: 0, cz: 0.05, hw: 2.1, hh: 1.2, pitchDegrees: 52, m)
            : rect(cx: 0, cz: -0.1, hw: 1.55, hh: 1.95, pitchDegrees: 56, m)
    }

    /// Looking at the closed cover while it opens.
    static func cover(rtl: Bool, _ m: ViewMetrics) -> CameraPose {
        let pw = BookDims.pageWidth, ph = BookDims.pageHeight
        return rect(cx: rtl ? -pw / 2 : pw / 2, cz: 0, hw: pw / 2 + 0.2, hh: ph / 2 + 0.1, pitchDegrees: 62, y: 0.3, m)
    }

    /// Reading page `page` (0-based: even pages are on the right, odd on the left, mirrored for right-to-left books).
    /// `surfaceY` is the height of that page's surface (`BookShape.surfaceY`); `pan` is the current landscape scroll.
    static func reading(page: Int, rtl: Bool, focus: Bool, surfaceY: Double, pan: Double, _ m: ViewMetrics) -> ReadingFrame {
        let pw = BookDims.pageWidth, ph = BookDims.pageHeight
        let rtlSign = rtl ? -1.0 : 1.0
        let onRight = page % 2 == 0
        let cx = rtlSign * (onRight ? pw / 2 : -pw / 2)
        let pitch = focus ? 66.0 : 58.0
        if m.isWide {
            // Landscape is short, so a whole page would be tiny: fill about half the width with the page (the neighbouring
            // page stays visible beside it) and let the reader scroll down it.
            let frac = focus ? 0.56 : 0.5
            let hw = (pw / 2 + 0.03) / frac
            let t0 = rect(cx: cx, cz: 0, hw: hw, hh: 0.05, pitchDegrees: pitch, y: surfaceY, m)
            let fov = radians(m.fovDegrees)
            let delta = t0.position - t0.look
            let d = (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
            let halfZ = (d * tan(fov / 2) * m.usableFraction) / sin(radians(pitch))
            let panLimit = max(0, ph / 2 - halfZ + 0.06)
            let pxPerZ = (Double(m.size.height) * m.usableFraction) / (2 * halfZ)
            let clamped = BookMath.clamp(pan, -panLimit, panLimit)
            let pose = rect(cx: cx, cz: clamped, hw: hw, hh: 0.05, pitchDegrees: pitch, y: surfaceY, m)
            return ReadingFrame(pose: pose, panLimit: panLimit, pxPerZ: pxPerZ, pan: clamped)
        }
        let fit = focus ? 0.5 * 1.02 : 0.5 * 1.1
        let pose = rect(cx: cx, cz: 0, hw: fit, hh: ph / 2 + 0.02, pitchDegrees: pitch, y: surfaceY, m)
        return ReadingFrame(pose: pose, panLimit: 0, pxPerZ: 1, pan: 0)
    }

    /// Where book `index` lies on the desk in the menu: position on the desk plane and rotation about the vertical axis.
    static func menuSlot(index: Int, wide: Bool) -> (x: Double, z: Double, ry: Double) {
        let slots: [(x: Double, z: Double, ry: Double)] = wide
            ? [(-0.82, 0.1, 0.12), (0.86, -0.05, -0.1)]   // first book left, second right
            : [(-0.2, 0.85, 0.10), (0.25, -1.05, -0.08)]  // first book near, second behind
        if index < slots.count { return slots[index] }
        return (Double(index) * 1.2, -Double(index), 0)
    }
}
