import CoreGraphics
import Foundation

/// What the tour drives: the scene's controller and the commands the HUD buttons send. The app's host talks to the real
/// `BooksSceneModel`; tests use a host that ticks the controller by hand.
@MainActor
protocol TourHost: AnyObject {
    var state: SceneState { get }
    var controller: BookSceneController { get }
    func send(_ command: SceneCommand)
    /// Lets `seconds` of scene time pass.
    func wait(_ seconds: Double) async
    /// Seconds on the clock the touch layer uses.
    var clock: Double { get }
}

/// The things a tour step can do: touch the scene through the same entry points a finger uses, press HUD buttons, wait.
@MainActor
final class TourContext {
    let host: TourHost
    /// Shows or hides the finger ring at a point of the view.
    var ring: (CGPoint?) -> Void = { _ in }

    init(host: TourHost) {
        self.host = host
    }

    var state: SceneState { host.state }
    var controller: BookSceneController { host.controller }

    func send(_ command: SceneCommand) { host.send(command) }
    func wait(_ seconds: Double) async { await host.wait(seconds) }

    /// Polls until `condition` holds or `timeout` seconds of scene time have passed.
    func waitUntil(timeout: Double, _ condition: () -> Bool) async -> Bool {
        var waited = 0.0
        while waited < timeout {
            if condition() { return true }
            await wait(0.05)
            waited += 0.05
        }
        return condition()
    }

    // MARK: Touch

    func tap(_ point: CGPoint) async {
        ring(point)
        controller.pointerDown(point, touch: true, time: host.clock)
        await wait(0.07)
        controller.pointerUp(point, time: host.clock)
        await wait(0.12)
        ring(nil)
    }

    /// A finger dragged along `path` over `seconds`: down at the first point, a move every frame, up at the last.
    func drag(_ path: [CGPoint], seconds: Double) async {
        guard let first = path.first, let last = path.last else { return }
        ring(first)
        controller.pointerDown(first, touch: true, time: host.clock)
        await wait(0.04)
        let frames = max(2, Int(seconds * 60))
        for k in 1...frames {
            let p = Self.point(on: path, at: Double(k) / Double(frames))
            ring(p)
            controller.pointerMove(p, time: host.clock)
            await wait(seconds / Double(frames))
        }
        controller.pointerUp(last, time: host.clock)
        await wait(0.1)
        ring(nil)
    }

    func swipe(from a: CGPoint, to b: CGPoint, seconds: Double) async {
        await drag([a, b], seconds: seconds)
    }

    /// The point a fraction `t` (0...1) of the way along a polyline.
    static func point(on path: [CGPoint], at t: Double) -> CGPoint {
        guard path.count > 1 else { return path.first ?? .zero }
        let scaled = min(max(t, 0), 1) * Double(path.count - 1)
        let i = min(Int(scaled), path.count - 2)
        let f = CGFloat(scaled - Double(i))
        return CGPoint(x: path[i].x + (path[i + 1].x - path[i].x) * f, y: path[i].y + (path[i + 1].y - path[i].y) * f)
    }

    /// Pinch in small steps from `from` to `to` (a zoom factor, relative to now) about the view centre.
    func pinch(by total: Double, seconds: Double) async {
        let size = controller.camera.size
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let steps = max(2, Int(seconds * 30))
        let each = pow(total, 1 / Double(steps))
        ring(centre)
        for _ in 0..<steps {
            controller.pinchChanged(scale: each, at: centre)
            await wait(seconds / Double(steps))
        }
        controller.pinchEnded(at: centre)
        await wait(0.3)
        ring(nil)
    }

    func twoFingerPan(by delta: CGSize, seconds: Double) async {
        let steps = max(2, Int(seconds * 60))
        for _ in 0..<steps {
            controller.panChanged(by: CGSize(width: delta.width / CGFloat(steps), height: delta.height / CGFloat(steps)))
            await wait(seconds / Double(steps))
        }
        controller.panEnded(velocity: .zero)
        await wait(0.3)
    }

    // MARK: Looking at the scene

    var viewCentre: CGPoint {
        CGPoint(x: controller.camera.size.width / 2, y: controller.camera.size.height / 2)
    }

    /// Indexes of the pages in view while reading page `index`: the right-hand one and its left neighbour.
    func visiblePages() -> [Int] {
        guard let entry = controller.current else { return [] }
        let i = controller.pageIndex
        let pair = i % 2 == 0 ? [i, i - 1] : [i, i + 1]
        return pair.filter { entry.pages.indices.contains($0) }
    }

    /// Screen position of the first tap target of a kind on the pages in view.
    func firstTarget(term: Bool) -> CGPoint? {
        guard let entry = controller.current else { return nil }
        for index in visiblePages() {
            for region in controller.pageImage(entry, index)?.hits ?? [] {
                let matches: Bool
                switch region.kind {
                case .term: matches = term
                case .recall: matches = !term
                }
                guard matches else { continue }
                if let p = controller.screenPoint(pageIndex: index, px: Double(region.rect.midX), py: Double(region.rect.midY)),
                   p.x > 8, p.y > 8, p.x < controller.camera.size.width - 8, p.y < controller.camera.size.height - 8 {
                    return p
                }
            }
        }
        return nil
    }

    /// A readable line about where the scene is, for the log.
    func observed() -> String {
        let s = state
        let free = controller.free
        return "mode=\(s.mode.rawValue) page=\(s.page)/\(s.pageCount) tool=\(s.tool ?? "none") focus=\(s.focus) recall=\(s.recall) level=\(s.level.rawValue) textSize=\(s.textSize.rawValue) zoom=\(String(format: "%.2f", free.zoom)) canNext=\(s.canNext) canPrev=\(s.canPrev)"
    }
}
