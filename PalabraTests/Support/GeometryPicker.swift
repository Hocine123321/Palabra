import CoreGraphics
import SceneKit
import simd
@testable import Palabra

/// A `ScenePicker` that answers from the scene's own geometry (no renderer), so scripted taps and drags work headless.
@MainActor
final class GeometryPicker: ScenePicker {
    unowned let controller: BookSceneController

    init(controller: BookSceneController) { self.controller = controller }

    func bookID(at point: CGPoint) -> String? {
        var best: (id: String, d: Double)?
        for entry in controller.entries {
            guard let p = controller.screenPoint(ofBook: entry.book.id) else { continue }
            let d = hypot(Double(p.x - point.x), Double(p.y - point.y))
            if d < 90, best == nil || d < best!.d { best = (entry.book.id, d) }
        }
        return best?.id
    }

    func pageHit(at point: CGPoint) -> PageHit? {
        guard let entry = controller.current else { return nil }
        let rtl = entry.book.isRightToLeft
        // The turned-leaf count decides which two faces are showing.
        let turned = (controller.pageIndex + 1) / 2
        for side in [1, -1] {
            let surface = entry.node.surfaceY(side: side)
            guard let w = controller.camera.planePoint(through: point, y: surface) else { continue }
            let logicalX = rtl ? -w.x : w.x
            let front = logicalX >= 0
            guard front == (side == 1) else { continue }
            let pageIndex = front ? turned * 2 : turned * 2 - 1
            guard pageIndex >= 0, pageIndex < entry.pages.count else { continue }
            let uvx = front ? logicalX / BookDims.pageWidth : logicalX / BookDims.pageWidth + 1
            guard uvx >= 0, uvx <= 1 else { continue }
            let u = rtl ? 1 - uvx : uvx
            let py = (w.z + BookDims.pageHeight / 2) / BookDims.pageHeight * PageGeometry.height
            guard py >= 0, py <= PageGeometry.height else { continue }
            return PageHit(pageIndex: pageIndex, leaf: pageIndex / 2, front: front, px: u * PageGeometry.width, py: py)
        }
        return nil
    }

    func toolName(at point: CGPoint) -> String? {
        var best: (name: String, d: Double)?
        for (name, tool) in controller.tools where !controller.toolsRoot.isHidden {
            let w = tool.root.presentation.worldPosition
            guard let p = controller.camera.screenPoint(for: SIMD3(Double(w.x), Double(w.y), Double(w.z))) else { continue }
            let d = hypot(Double(p.x - point.x), Double(p.y - point.y))
            if d < 50, best == nil || d < best!.d { best = (name, d) }
        }
        return best?.name
    }
}
