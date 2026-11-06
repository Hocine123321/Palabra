import SceneKit
import UIKit

/// Daylight coming in through a window to the left of the desk (light mode only).
///
/// The desk sits in a room, so the sun should arrive the way it does in one: through panes. Two things make that read:
///  - a **gobo**, an invisible frame with crossbars that stands between the sun and the desk. It writes nothing to the screen but
///    still blocks light, so the sun's own shadow map lays the bars across the felt and the books;
///  - a soft warm **glow** lying on the desk, which makes the lit part of the felt feel sunlit (the shadow map only darkens).
/// The window's size and the sun's angle were found by simulation (`Layout.coverage`) so that every book in the menu is reached,
/// stays mostly bright, and still wears visible bars. Both fade out together with `amount`, which the enhancement layer lowers
/// while a book is read.
@MainActor
final class WindowLight {
    let root = SCNNode()
    private let gobo = SCNNode()
    private let patch = SCNNode()
    private let patchMaterial = SCNMaterial()
    private(set) var amount = 0.0
    private var time = 0.0

    /// Where the window is, and how it is divided. Pure numbers so tests can check the arrangement.
    struct Layout: Equatable {
        /// Panes across and down.
        var columns = 3 { didSet { columns = max(1, columns) } }
        var rows = 4 { didSet { rows = max(1, rows) } }
        /// Width of a crossbar as a share of the window.
        var bar = 0.03
        /// The window's size in desk units.
        ///
        /// Chosen by simulating the shadow of the bars on the desk (`WindowLightTests`): wide enough that the light reaches
        /// every book in the menu, with the bars shading about a fifth of each, in portrait and in landscape, so the window reads on the covers.
        var width = 5.2
        var height = 3.6
        /// Direction the sun travels (from the window to the desk), not normalised: about 50 degrees up, from the left.
        var direction = SIMD3<Double>(1, -1.2, -0.2)

        /// Cut-outs of the window's panes as fractions (x0, y0, x1, y1) of its width and height, bars excluded.
        var panes: [(x0: Double, y0: Double, x1: Double, y1: Double)] {
            // Bars are the same thickness across and down: `bar` of the shorter side.
            let thickness = bar * min(width, height)
            let barW = thickness / width
            let barH = thickness / height
            let paneW = (1 - barW * Double(columns + 1)) / Double(columns)
            let paneH = (1 - barH * Double(rows + 1)) / Double(rows)
            var out: [(Double, Double, Double, Double)] = []
            for r in 0..<rows {
                for c in 0..<columns {
                    let x0 = barW + Double(c) * (paneW + barW)
                    let y0 = barH + Double(r) * (paneH + barH)
                    out.append((x0, y0, x0 + paneW, y0 + paneH))
                }
            }
            return out
        }

        /// What the sun does to a point on the desk: shines through a pane, is stopped by a bar, or never reaches the window.
        enum Ray { case lit, barShadow, outside }

        /// Traces the sun back from `point` to the window (a plane `back` behind the desk centre, square to the sun).
        func ray(from point: SIMD3<Double>, back: Double = 2.7) -> Ray {
            let length = (direction.x * direction.x + direction.y * direction.y + direction.z * direction.z).squareRoot()
            let dn = direction / length
            let centre = -dn * back
            let z = -dn
            // The window's axes: x is horizontal in the plane, y is up in it.
            var x = SIMD3<Double>(z.z, 0, -z.x)   // up (0,1,0) cross z
            let xl = (x.x * x.x + x.z * x.z).squareRoot()
            x = SIMD3(x.x / xl, 0, x.z / xl)
            let y = SIMD3(z.y * x.z - z.z * x.y, z.z * x.x - z.x * x.z, z.x * x.y - z.y * x.x)
            // Walk from the point against the sun's travel until the window's plane.
            let t = ((centre - point) * z).sum() / (-dn * z).sum()
            let hit = point + (-dn) * t
            let rel = hit - centre
            let u = (rel * x).sum() / width + 0.5
            let v = (rel * y).sum() / height + 0.5
            guard u >= 0, u <= 1, v >= 0, v <= 1 else { return .outside }
            for pane in panes where u >= pane.x0 && u <= pane.x1 && v >= pane.y0 && v <= pane.y1 { return .lit }
            return .barShadow
        }

        /// Shares of a rectangle on the desk (centre, half-sizes) that are lit, barred and out of reach.
        func coverage(centre: SIMD2<Double>, half: SIMD2<Double>, steps: Int = 24) -> (lit: Double, bar: Double, outside: Double) {
            var lit = 0, bar = 0, outside = 0
            for i in 0..<steps {
                for j in 0..<steps {
                    let px = centre.x + (Double(i) / Double(steps - 1) * 2 - 1) * half.x
                    let pz = centre.y + (Double(j) / Double(steps - 1) * 2 - 1) * half.y
                    switch ray(from: SIMD3(px, 0.1, pz)) {
                    case .lit: lit += 1
                    case .barShadow: bar += 1
                    case .outside: outside += 1
                    }
                }
            }
            let n = Double(steps * steps)
            return (Double(lit) / n, Double(bar) / n, Double(outside) / n)
        }

        /// Share of the window that lets light through.
        var openShare: Double { panes.reduce(0) { $0 + ($1.x1 - $1.x0) * ($1.y1 - $1.y0) } }
    }

    let layout: Layout

    /// The sun, as seen from the desk centre, when the window is lit: from the left and in front, about 50 degrees up.
    static func sunPosition(centre: SCNVector3, layout: Layout = Layout()) -> SCNVector3 {
        let d = layout.direction
        let length = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        let distance = 5.2
        return SCNVector3(
            centre.x - Float(d.x / length * distance),
            centre.y - Float(d.y / length * distance),
            centre.z - Float(d.z / length * distance)
        )
    }

    init(layout: Layout = Layout()) {
        self.layout = layout
        buildGobo()
        buildPatch()
        root.addChildNode(gobo)
        root.addChildNode(patch)
        root.isHidden = true
    }

    // MARK: Building

    /// An invisible frame whose bars still block the sun.
    private func buildGobo() {
        let invisible = SCNMaterial()
        invisible.lightingModel = .constant
        invisible.colorBufferWriteMask = []
        invisible.writesToDepthBuffer = false
        invisible.isDoubleSided = true
        let w = layout.width, h = layout.height
        let barW = layout.bar * min(w, h)
        let barH = layout.bar * min(w, h)
        func bar(_ width: Double, _ height: Double, x: Double, y: Double) {
            let box = SCNBox(width: width, height: height, length: 0.05, chamferRadius: 0)
            box.materials = [invisible]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(Float(x), Float(y), 0)
            node.castsShadow = true
            gobo.addChildNode(node)
        }
        // Outer frame.
        bar(w, barH, x: 0, y: h / 2 - barH / 2)
        bar(w, barH, x: 0, y: -h / 2 + barH / 2)
        bar(barW, h, x: -w / 2 + barW / 2, y: 0)
        bar(barW, h, x: w / 2 - barW / 2, y: 0)
        // Dividers: the left edge of divider k is after k panes and k bars of the outer frame.
        let paneW = (w - barW * Double(layout.columns + 1)) / Double(layout.columns)
        for c in 1..<layout.columns {
            let left = -w / 2 + barW * Double(c) + paneW * Double(c)
            bar(barW, h, x: left + barW / 2, y: 0)
        }
        let paneH = (h - barH * Double(layout.rows + 1)) / Double(layout.rows)
        for r in 1..<layout.rows {
            let bottom = -h / 2 + barH * Double(r) + paneH * Double(r)
            bar(w, barH, x: 0, y: bottom + barH / 2)
        }
        aim(at: SCNVector3Zero)
    }

    /// Puts the gobo between the sun and `centre`, facing along the sun, so the bars land on whatever book is being shown.
    /// (`SceneLighting.aimShadow` moves the sun to the same spot with `sunPosition`.)
    func aim(at centre: SCNVector3) {
        let d = layout.direction
        let length = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        let back = 2.7
        gobo.position = SCNVector3(
            centre.x - Float(d.x / length * back), centre.y - Float(d.y / length * back), centre.z - Float(d.z / length * back)
        )
        gobo.look(at: SCNVector3(
            gobo.position.x + Float(d.x), gobo.position.y + Float(d.y), gobo.position.z + Float(d.z)
        ))
        aimPatch(at: centre)
    }

    /// A broad warm glow on the felt. It carries no pattern of its own: the bars come from the sun's shadow map, and drawing them
    /// twice would blur them. It only lifts the lit part of the desk so the room feels sunlit rather than merely less shaded.
    private func buildPatch() {
        let plane = SCNPlane(width: 5.6, height: 5.6)
        patchMaterial.lightingModel = .constant
        patchMaterial.diffuse.contents = SoftSprites.radial(UIColor(rgb: 0xffe2a0, alpha: 0.9), size: 128, falloff: 0.55)
        patchMaterial.blendMode = .add
        patchMaterial.writesToDepthBuffer = false
        patchMaterial.readsFromDepthBuffer = true
        patchMaterial.isDoubleSided = false
        patchMaterial.transparency = 0
        plane.materials = [patchMaterial]
        patch.geometry = plane
        // Lying flat on the felt, a hair above it, facing up.
        patch.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        patch.renderingOrder = 3
        patch.opacity = 1
        aimPatch(at: SCNVector3Zero)
    }

    private func aimPatch(at centre: SCNVector3) {
        patch.position = SCNVector3(centre.x - 0.2, 0.03, centre.z - 0.1)
    }

    // MARK: Per frame

    /// `target` is how much of the window should show (0...1). Eases toward it and breathes a little, like a passing cloud.
    func update(dt: Double, target: Double) {
        time += dt
        amount += (target - amount) * min(1, dt * (target > amount ? 2.0 : 9))
        let visible = amount > 0.01
        root.isHidden = !visible
        guard visible else { return }
        // A cloud drifting past: the glow never drops below ~90%, so it is a gentle shimmer and not a flicker.
        let breath = 0.93 + 0.05 * sin(time * 0.31) + 0.02 * sin(time * 0.83 + 1.1)
        patchMaterial.transparency = CGFloat(amount * breath * 0.34)
        // The bars are in the way of the sun for as long as the window shows; the sun glides to and from its window place with
        // `amount` (`SceneLighting.setWindowAmount`), so the shadow never jumps.
        gobo.isHidden = false
    }
}
