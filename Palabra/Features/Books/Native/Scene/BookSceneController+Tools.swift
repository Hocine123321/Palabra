import CoreGraphics
import Foundation
import SceneKit
import simd

/// The lens, the ruler and the bookmark card (`setTool`, `_useTool`, `_stowTool` in app.js).
extension BookSceneController {
    private var pw: Double { BookDims.pageWidth }
    private var ph: Double { BookDims.pageHeight }
    private var rtlSign: Double { (current?.book.isRightToLeft ?? false) ? -1 : 1 }

    // MARK: Picking up and putting away

    func setTool(_ requested: String?) {
        guard state.mode == .reading else { return }
        var name = requested
        if name == state.tool { name = nil }
        if let previous = state.tool { stowTool(previous) }
        state.tool = name
        if let name { useTool(name) }
        emit()
    }

    func returnTools() {
        if let tool = state.tool {
            stowTool(tool)
            state.tool = nil
        }
    }

    private func fly(_ tool: ToolNode, to position: SIMD3<Double>, yaw: Double, lift: Double, duration: Double, then done: (() -> Void)? = nil) {
        let fromP = tool.root.position
        let fromQ = tool.root.simdOrientation
        let toQ = simd_quatf(angle: Float(yaw), axis: SIMD3<Float>(0, 1, 0))
        tweens.add(duration: duration, ease: .inOut, onUpdate: { k in
            let x = BookMath.lerp(Double(fromP.x), position.x, k)
            let y = BookMath.lerp(Double(fromP.y), position.y, k) + sin(k * .pi) * lift
            let z = BookMath.lerp(Double(fromP.z), position.z, k)
            tool.root.position = SCNVector3(Float(x), Float(y), Float(z))
            tool.root.simdOrientation = simd_slerp(fromQ, toQ, Float(k))
        }, onDone: done)
    }

    private func stowTool(_ name: String) {
        guard let tool = tools[name] else { return }
        if name == "lens" { lens.setMagnifying(false) }
        if name == "ruler" { setBand(on: false) }
        if name == "bookmark", let id = current?.book.id { config.bookmarks[id] = nil }
        var rest = SIMD3<Double>(Double(tool.restPosition.x), Double(tool.restPosition.y), Double(tool.restPosition.z))
        if state.focus { rest.y -= 0.6 }
        fly(tool, to: rest, yaw: Double(tool.restYaw), lift: 0.35, duration: 0.8) { [weak self] in
            if self?.state.focus == true { tool.root.isHidden = true }
        }
    }

    private func useTool(_ name: String) {
        guard let entry = current, let tool = tools[name] else { return }
        tool.root.isHidden = false
        tool.root.opacity = 1
        let side = pageIndex % 2 == 0 ? 1.0 : -1.0
        let rs = rtlSign
        let surface = entry.node.surfaceY(side: Int(side))
        let target: SIMD3<Double>
        switch name {
        case "lens":
            target = SIMD3(rs * side * pw * 0.5, surface + 0.26, 0.1)
            lensPos = (target.x, target.z)
            lens.setMagnifying(true)
            lens.setTone(isDark ? 0.78 : 0.92)
            lensRefresh(force: true)
        case "ruler":
            rulerZ = -0.25
            target = SIMD3(rs * side * pw * 0.5, surface + 0.012, rulerZ)
            setBand(on: true)
        default:
            // The card slides in at the head of the page, its tassel hanging over the fore edge.
            target = SIMD3(rs * side * (pw - 0.16), surface + 0.01, -ph / 2 + 0.17)
            placeBookmark()
        }
        fly(tool, to: target, yaw: 0, lift: 0.45, duration: 0.85) { [weak self] in
            if name == "lens" { self?.lensRefresh(force: true) }
        }
    }

    private func placeBookmark() {
        guard let entry = current, entry.pages.indices.contains(pageIndex) else { return }
        let base = entry.pages[pageIndex].baseID
        config.bookmarks[entry.book.id] = base
        post(.bookmark(bookID: entry.book.id, pageID: base))
    }

    // MARK: Ruler

    func setBand(on: Bool) {
        bandOn = on
        if on { updateBand() } else { current?.node.setBand(face: nil, centreV: 0, halfV: 0) }
    }

    func updateBand() {
        guard let entry = current, bandOn else { return }
        let v = 1 - (rulerZ + ph / 2) / ph
        let half = (ToolFactory.rulerWidth / 2) / ph
        entry.node.setBand(face: (pageIndex / 2, pageIndex % 2 == 0), centreV: v, halfV: half * 1.15)
    }

    func moveRuler(_ point: CGPoint) {
        guard let entry = current else { return }
        let side = pageIndex % 2 == 0 ? 1 : -1
        guard let p = camera.planePoint(through: point, y: entry.node.surfaceY(side: side)) else { return }
        rulerZ = BookMath.clamp(p.z, -ph / 2 + 0.1, ph / 2 - 0.1)
        ruler.root.position.z = Float(rulerZ)
        updateBand()
    }

    // MARK: Lens

    func moveLens(_ point: CGPoint, touch: Bool) {
        guard let entry = current else { return }
        let rs = rtlSign
        let side = lensPos.x * rs >= 0 ? 1 : -1
        guard let p = camera.planePoint(through: point, y: entry.node.surfaceY(side: side)) else { return }
        let offset = touch ? -0.38 : 0 // keep the lens clear of a finger
        let limit = pw
        let x = BookMath.clamp(p.x, -limit * 1.02, limit * 1.02)
        let z = BookMath.clamp(p.z + offset, -ph / 2 + 0.05, ph / 2 - 0.05)
        lensPos = (x, z)
        let surface = entry.node.surfaceY(side: x * rs >= 0 ? 1 : -1)
        lens.tool.root.position = SCNVector3(Float(x), Float(surface + 0.26), Float(z))
        lensRefresh(force: false)
    }

    /// Which page the glass looks at and the key of its bitmap.
    private func lensTarget() -> (pageIndex: Int, side: Int)? {
        guard let entry = current else { return nil }
        let side = lensPos.x * rtlSign >= 0 ? 1 : -1
        let spread = Int((Double(pageIndex) / 2).rounded(.up))
        let index = side > 0 ? min(2 * spread, entry.pages.count) : 2 * spread - 1
        return (index, side)
    }

    private func lensKey(_ index: Int, _ entry: Entry) -> String {
        "\(entry.book.id):\(index):\(recall.isEnabled):\(recall.level.rawValue):\(isDark)"
    }

    /// Makes sure the glass has the right bitmap: draws it (everything revealed, high resolution) when it is not cached.
    func lensRefresh(force: Bool) {
        guard let entry = current, state.tool == "lens", let target = lensTarget() else { return }
        let key = lensKey(target.pageIndex, entry)
        if !force, key == lensShownKey { return }
        lensShownKey = key
        guard target.pageIndex >= 0, target.pageIndex < entry.pages.count else {
            lens.setImage(nil)
            return
        }
        if let image = lensImageCache[key] {
            lens.setImage(image)
            return
        }
        guard !lensPending.contains(key) else { return }
        lensPending.insert(key)
        let phys = entry.pages[target.pageIndex]
        var options = self.options(entry, target.pageIndex)
        options.revealAll = true
        options.density = 1.6
        let box = LensBox((phys, options))
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = PageRenderer.draw(box.value.0, box.value.1)
            let image = LensImage(result.image)
            await MainActor.run {
                guard let self else { return }
                self.lensPending.remove(key)
                if self.lensImageCache.count > 6 { self.lensImageCache.removeAll() }
                self.lensImageCache[key] = image.value
                if self.lensShownKey == key { self.lens.setImage(image.value) }
            }
        }
    }

    /// Every frame: the glass follows the real view ray down to the page plane.
    func updateLens() {
        guard let entry = current, state.tool == "lens" else { return }
        let rs = rtlSign
        let cam = camera.pose.position
        let gc = lens.tool.root.position
        let g = SIMD3<Double>(Double(gc.x), Double(gc.y), Double(gc.z))
        let side0 = g.x * rs >= 0 ? 1 : -1
        let planeY = entry.node.surfaceY(side: side0)
        guard abs(g.y - cam.y) > 1e-6 else { return }
        let k = (planeY - cam.y) / (g.y - cam.y)
        let cx = cam.x + (g.x - cam.x) * k, cz = cam.z + (g.z - cam.z) * k
        // The bitmap on the glass is the page its centre is over; the window is computed for that page.
        guard let target = lensTarget() else { return }
        let side = target.side
        let uvx = rs * cx / pw + (side < 0 ? 1 : 0)
        let u0 = entry.book.isRightToLeft ? 1 - uvx : uvx
        let v0 = (cz + ph / 2) / ph
        lens.setWindow(u0: u0, v0: v0)
        lens.setTone(isDark ? 0.78 : 0.92)
    }
}

private final class LensBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class LensImage: @unchecked Sendable {
    let value: CGImage
    init(_ value: CGImage) { self.value = value }
}
