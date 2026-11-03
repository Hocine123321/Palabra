import CoreGraphics
import Foundation
import SceneKit

/// A point on a leaf face under a finger: which page it is and where on the 1280 x 1820 page bitmap.
struct PageHit: Equatable {
    var pageIndex: Int
    var leaf: Int
    var front: Bool
    var px: Double
    var py: Double
}

/// What needs a renderer to answer (the view implements it with `SCNView.hitTest`).
@MainActor
protocol ScenePicker: AnyObject {
    func bookID(at point: CGPoint) -> String?
    func pageHit(at point: CGPoint) -> PageHit?
}

/// One finger from touch-down to lift (`this.drag` of app.js).
struct PointerDrag {
    enum Mode { case turn, pan, freePan }

    var start: CGPoint
    var touch: Bool
    var moved = false
    var mode: Mode?
    var bookID: String?
    var page: PageHit?
    var edge = false
    var x0 = 0.0
    var leaf = 0
    var side = 1
    var lastP = 0.0
    var lastT = 0.0
    /// Page-turn speed in progress per second.
    var velocity = 0.0
    var pan0 = 0.0
    var lastPoint = CGPoint.zero
    var lastMoveTime = 0.0
    var panVelocity = CGSize.zero
}

extension BookSceneController {
    private var pw: Double { BookDims.pageWidth }
    private static let slop = 8.0

    // MARK: Entry points

    func pointerDown(_ point: CGPoint, touch: Bool, time: Double) {
        var d = PointerDrag(start: point, touch: touch)
        defer { drag = d }
        switch state.mode {
        case .menu:
            d.bookID = picker?.bookID(at: point)
            hoverBook = d.bookID
        case .reading:
            guard let entry = current else { return }
            let hit = picker?.pageHit(at: point)
            d.page = hit
            let side = pageIndex % 2 == 0 ? 1 : -1
            let hitSide = hit.map { $0.front ? 1 : -1 } ?? side
            let rs = entry.book.isRightToLeft ? -1.0 : 1.0
            if let pp = camera.planePoint(through: point, y: entry.node.surfaceY(side: hitSide)) {
                d.x0 = pp.x * rs
                if let hit {
                    // Pressing the outer part of a page grabs it to turn.
                    let fraction = hit.px / PageGeometry.width
                    let gutterLeft = hit.front != entry.book.isRightToLeft
                    if gutterLeft ? fraction > 0.78 : fraction < 0.22 { d.edge = true }
                }
            }
        default:
            break
        }
        _ = time
    }

    func pointerMove(_ point: CGPoint, time: Double) {
        guard var d = drag else { return }
        defer { drag = d }
        let dx = Double(point.x - d.start.x), dy = Double(point.y - d.start.y)
        if !d.moved, hypot(dx, dy) > Self.slop { d.moved = true }
        if d.mode == .freePan {
            followFreePan(&d, point, time: time)
            return
        }
        guard d.moved else { return }
        // Zoomed in, a one-finger drag moves the view (except from a page edge, which still turns the leaf).
        if d.mode == nil, canFreeMove, free.zoom > 1.05, !d.edge, state.mode == .menu || state.mode == .reading {
            d.mode = .freePan
            d.lastPoint = d.start
            d.lastMoveTime = time
            followFreePan(&d, point, time: time)
            return
        }
        guard state.mode == .reading, current != nil else { return }
        switch d.mode {
        case .turn:
            dragTurn(&d, point, time: time)
        case .pan:
            panBy(d.pan0 - dy / max(pxPerZ, 1e-6))
        case .freePan:
            break
        case nil:
            let horizontal = abs(dx) > abs(dy) * 1.1
            if !d.edge, !horizontal, panLimit > 0 {
                d.mode = .pan
                d.pan0 = panZ
            } else if d.edge || horizontal {
                beginTurn(&d, point, time: time)
            }
        }
    }

    private func followFreePan(_ d: inout PointerDrag, _ point: CGPoint, time: Double) {
        let delta = CGSize(width: point.x - d.lastPoint.x, height: point.y - d.lastPoint.y)
        let dt = max(0.001, time - d.lastMoveTime)
        d.panVelocity = CGSize(width: delta.width / dt, height: delta.height / dt)
        d.lastPoint = point
        d.lastMoveTime = time
        panChanged(by: delta)
    }

    func pointerUp(_ point: CGPoint, time: Double) {
        guard let d = drag else { return }
        drag = nil
        switch state.mode {
        case .menu:
            let id = picker?.bookID(at: point)
            if d.mode == .freePan { panEnded(velocity: d.panVelocity) }
            if let id, id == d.bookID, !d.moved { openBook(id: id, pageID: nil) }
            hoverBook = nil
        case .reading:
            if d.mode == .turn {
                finishTurn(d)
            } else if d.mode == .freePan {
                panEnded(velocity: d.panVelocity)
            } else if d.mode == .pan {
                break
            } else if !d.moved {
                tapPage(at: point)
            }
        default:
            break
        }
    }

    func pointerCancel() {
        if let d = drag, d.mode == .turn, let entry = current {
            // Let go of the page where it is: settle to the nearer side.
            finishTurn(d, entry: entry)
        }
        drag = nil
        hoverBook = nil
        setPeek(nil)
    }

    // MARK: Panning (landscape reading)

    func panBy(_ z: Double) {
        guard current != nil, state.mode == .reading else { return }
        panZ = BookMath.clamp(z, -panLimit, panLimit)
        moveCamera(readTarget(pageIndex), duration: 0)
    }

    // MARK: Turning by hand

    private func beginTurn(_ d: inout PointerDrag, _ point: CGPoint, time: Double) {
        guard let entry = current else { return }
        let rs = entry.book.isRightToLeft ? -1.0 : 1.0
        // Dragging toward the spine turns forward from a right page; away from it turns back from a left page.
        let side = d.page.map { $0.front ? 1 : -1 } ?? (pageIndex % 2 == 0 ? 1 : -1)
        let flipped = (0..<entry.node.leafCount).filter { entry.node.leafProgress($0) >= 0.5 }.count
        let leaf: Int
        if side > 0 {
            leaf = flipped
            guard leaf < entry.node.leafCount else { return }
        } else {
            leaf = flipped - 1
            guard leaf >= 0 else { return }
        }
        guard leafTweenIsRunning(leaf) == false else { return }
        d.mode = .turn
        d.leaf = leaf
        d.side = side
        d.lastP = entry.node.leafProgress(leaf)
        d.lastT = time
        d.velocity = 0
        setPeek(nil)
        closeTerm()
        let pp = camera.planePoint(through: point, y: entry.node.surfaceY(side: side))
        d.x0 = pp.map { $0.x * rs } ?? 0
        dragTurn(&d, point, time: time)
        // The jump from the resting leaf to the finger is not a flick.
        d.velocity = 0
    }

    private func dragTurn(_ d: inout PointerDrag, _ point: CGPoint, time: Double) {
        guard let entry = current else { return }
        let rs = entry.book.isRightToLeft ? -1.0 : 1.0
        guard let pp = camera.planePoint(through: point, y: entry.node.surfaceY(side: d.side)) else { return }
        let x = pp.x * rs
        let tip = d.side > 0 ? pw - (d.x0 - x) : -pw + (x - d.x0)
        let p = BookMath.clamp(acos(BookMath.clamp(tip / pw, -1, 1)) / Double.pi, 0, 1)
        let grab = d.page.map { BookMath.clamp($0.py / PageGeometry.height, 0, 1) } ?? 0.8
        entry.node.setGrab(d.leaf, grab)
        let dt = max(0.001, time - d.lastT)
        d.velocity = (p - d.lastP) / dt
        d.lastP = p
        d.lastT = time
        entry.node.setLeafProgress(d.leaf, p)
        entry.node.layout()
    }

    private func finishTurn(_ d: PointerDrag, entry: Entry? = nil) {
        guard let entry = entry ?? current else { return }
        let p = entry.node.leafProgress(d.leaf)
        let forward = d.side > 0
        var complete = forward ? (p > 0.42 || d.velocity > 0.9) : (p < 0.58 || d.velocity < -0.9)
        if forward, d.velocity < -0.9 { complete = false }
        if !forward, d.velocity > 0.9 { complete = false }
        let to = complete ? (forward ? 1.0 : 0.0) : (forward ? 0.0 : 1.0)
        animateLeaf(entry, d.leaf, to: to, duration: 0.5 * abs(to - p) + 0.18, delay: 0)
        guard complete else { return }
        // Forward from a right page lands on the next left page; back from a left page lands on the previous right page.
        let f = Int((Double(pageIndex) / 2).rounded(.up))
        let target = forward ? 2 * f + 1 : 2 * (f - 1)
        pageIndex = Int(BookMath.clamp(Double(target), 0, Double(entry.pages.count - 1)))
        ensureTextures(entry, around: pageIndex, immediate: false)
        moveCamera(readTarget(pageIndex), duration: 0.8)
        afterNavigate()
    }

    // MARK: Peek (a lifted page corner)

    func setPeek(_ target: (leaf: Int, z: Double)?) {
        guard let entry = current else { return }
        peekLeaf = target?.leaf
        for leaf in 0..<entry.node.leafCount {
            let want = target?.leaf == leaf ? 1.0 : 0.0
            if let target, target.leaf == leaf { entry.node.setGrab(leaf, BookMath.clamp(target.z, 0, 1)) }
            let now = entry.node.peek(leaf)
            if abs(now - want) > 0.001 {
                var next = now + (want - now) * 0.25
                if abs(next - want) < 0.01 { next = want }
                entry.node.setPeek(leaf, next)
            }
        }
        entry.node.layout()
    }

    /// Lets lifted corners fall back once nothing holds them (called every frame while reading).
    func settlePeek() {
        guard let entry = current, state.mode == .reading else { return }
        var any = false
        for leaf in 0..<entry.node.leafCount where entry.node.peek(leaf) > 0.002 && peekLeaf != leaf {
            entry.node.setPeek(leaf, entry.node.peek(leaf) * 0.7)
            any = true
        }
        if any { entry.node.layout() }
    }

    // MARK: Taps on a page

    func tapPage(at point: CGPoint) {
        guard let entry = current, let hit = picker?.pageHit(at: point) else {
            closeTerm()
            return
        }
        let hits = pageImage(entry, hit.pageIndex)?.hits ?? []
        let spot = CGPoint(x: hit.px, y: hit.py)
        for region in hits.reversed() where region.rect.contains(spot) {
            switch region.kind {
            case .term(let id):
                if hit.pageIndex == pageIndex { openTerm(id: id) } else { closeTerm() }
                return
            case .recall(let key, _):
                guard entry.pages.indices.contains(hit.pageIndex) else { return }
                let phys = entry.pages[hit.pageIndex]
                recall.toggle(key: key, pageID: phys.id)
                state.revealed = recall.isPageRevealed(phys.id)
                redrawVisible()
                emit()
                return
            }
        }
        closeTerm()
    }
}
