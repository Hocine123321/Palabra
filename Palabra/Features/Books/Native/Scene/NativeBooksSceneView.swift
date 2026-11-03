import SceneKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// An `SCNView` that reports its size, so the camera can follow rotations and split-screen changes.
final class NativeSCNView: SCNView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

/// The native SceneKit desk (`BookSceneController`) as a SwiftUI view: the counterpart of `BooksSceneView` (web).
struct NativeBooksSceneView: UIViewRepresentable {
    let model: BooksSceneModel
    let reducedMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NativeSCNView {
        let controller = model.startNative(reducedMotion: reducedMotion)
        let view = NativeSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = controller.scene
        view.pointOfView = controller.camera.node
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isAccessibilityElement = false
        view.accessibilityIdentifier = "booksSceneNative"
        view.contentScaleFactor = Self.scale(for: controller.quality, view: view)
        view.onLayout = { [weak controller] size in controller?.setSize(size) }
        controller.onQualityChange = { [weak view, weak controller] quality in
            guard let view, let controller else { return }
            view.contentScaleFactor = Self.scale(for: controller.quality, view: view)
            _ = quality
        }
        context.coordinator.attach(view: view, model: model, controller: controller)
        return view
    }

    func updateUIView(_ view: NativeSCNView, context: Context) {}

    static func dismantleUIView(_ view: NativeSCNView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private static func scale(for quality: SceneQuality, view: UIView) -> CGFloat {
        let screen = view.window?.screen.scale ?? UIScreen.main.scale
        return quality == .saver ? min(screen, 1.25) : min(screen, 2.5)
    }

    @MainActor
    final class Coordinator: NSObject, ScenePicker, UIGestureRecognizerDelegate {
        private weak var view: SCNView?
        private weak var model: BooksSceneModel?
        private weak var controller: BookSceneController?
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0

        func attach(view: SCNView, model: BooksSceneModel, controller: BookSceneController) {
            self.view = view
            self.model = model
            self.controller = controller
            controller.picker = self
            let pointer = PointerGesture()
            pointer.cancelsTouchesInView = false
            pointer.delegate = self
            pointer.onEvent = { [weak self] event, point, touch in self?.pointer(event, point, touch) }
            view.addGestureRecognizer(pointer)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            view.addGestureRecognizer(pan)
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            double.numberOfTapsRequired = 2
            double.delegate = self
            view.addGestureRecognizer(double)
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func detach() {
            link?.invalidate()
            link = nil
        }

        fileprivate func step(_ link: CADisplayLink) {
            let now = link.timestamp
            let dt = last == 0 ? 1.0 / 60 : now - last
            last = now
            controller?.tick(dt: dt)
        }

        private func pointer(_ event: PointerGesture.Event, _ point: CGPoint, _ touch: Bool) {
            guard let controller else { return }
            let time = CACurrentMediaTime()
            switch event {
            case .down: controller.pointerDown(point, touch: touch, time: time)
            case .move: controller.pointerMove(point, time: time)
            case .up: controller.pointerUp(point, time: time)
            case .cancel: controller.pointerCancel()
            }
        }

        // MARK: Free view gestures

        private var lastScale: CGFloat = 1

        @objc private func pinched(_ g: UIPinchGestureRecognizer) {
            guard let controller, let view else { return }
            switch g.state {
            case .began:
                lastScale = 1
            case .changed:
                controller.pinchChanged(scale: Double(g.scale / lastScale), at: g.location(in: view))
                lastScale = g.scale
            case .ended, .cancelled:
                controller.pinchEnded(at: g.location(in: view))
            default:
                break
            }
        }

        private var lastTranslation = CGPoint.zero

        @objc private func panned(_ g: UIPanGestureRecognizer) {
            guard let controller, let view else { return }
            switch g.state {
            case .began:
                lastTranslation = .zero
            case .changed:
                let t = g.translation(in: view)
                controller.panChanged(by: CGSize(width: t.x - lastTranslation.x, height: t.y - lastTranslation.y))
                lastTranslation = t
            case .ended:
                let v = g.velocity(in: view)
                controller.panEnded(velocity: CGSize(width: v.x, height: v.y))
            default:
                break
            }
        }

        @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            controller?.doubleTapped(at: g.location(in: view))
        }

        nonisolated func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            // The pointer gesture and the double tap watch alongside everything; pinch and two-finger pan work together.
            !(a is UIPinchGestureRecognizer && b is UITapGestureRecognizer) && !(a is UITapGestureRecognizer && b is UIPinchGestureRecognizer)
        }

        // MARK: ScenePicker

        func bookID(at point: CGPoint) -> String? {
            guard let view, let controller else { return nil }
            return controller.bookID(at: point, in: view)
        }

        func pageHit(at point: CGPoint) -> PageHit? {
            guard let view, let controller, let entry = controller.current else { return nil }
            let options: [SCNHitTestOption: Any] = [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .backFaceCulling: false,
                .rootNode: entry.node.root,
                .sortResults: true,
            ]
            let eye = controller.camera.pose.position
            for hit in view.hitTest(point, options: options) {
                guard let face = entry.node.face(of: hit.node) else { continue }
                // Both faces of a leaf are in the scene: only the one turned toward the camera counts.
                let toEye = SIMD3<Double>(eye.x - Double(hit.worldCoordinates.x), eye.y - Double(hit.worldCoordinates.y), eye.z - Double(hit.worldCoordinates.z))
                let normal = SIMD3<Double>(Double(hit.worldNormal.x), Double(hit.worldNormal.y), Double(hit.worldNormal.z))
                guard normal.x * toEye.x + normal.y * toEye.y + normal.z * toEye.z > 0 else { continue }
                let uv = hit.textureCoordinates(withMappingChannel: 0)
                return PageHit(
                    pageIndex: face.leaf * 2 + (face.front ? 0 : 1), leaf: face.leaf, front: face.front,
                    px: Double(uv.x) * PageGeometry.width, py: Double(uv.y) * PageGeometry.height
                )
            }
            return nil
        }
    }
}

/// Reports the first finger (or the mouse / pointer) from touch-down to lift, without stealing touches from anything else.
final class PointerGesture: UIGestureRecognizer {
    enum Event { case down, move, up, cancel }

    var onEvent: ((Event, CGPoint, Bool) -> Void)?
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if tracked != nil {
            // A second finger: this is a pinch, not a drag.
            if let t = tracked { onEvent?(.cancel, t.location(in: view), true) }
            tracked = nil
            state = .cancelled
            return
        }
        guard let touch = touches.first else { return }
        tracked = touch
        state = .began
        onEvent?(.down, touch.location(in: view), touch.type != .indirectPointer)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        state = .changed
        onEvent?(.move, t.location(in: view), t.type != .indirectPointer)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        tracked = nil
        state = .ended
        onEvent?(.up, t.location(in: view), t.type != .indirectPointer)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        tracked = nil
        state = .cancelled
        onEvent?(.cancel, t.location(in: view), true)
    }

    override func reset() {
        tracked = nil
    }
}

/// `CADisplayLink` retains its target; this keeps it from keeping the coordinator alive.
private final class DisplayLinkTarget: NSObject {
    private weak var owner: NativeBooksSceneView.Coordinator?

    init(_ owner: NativeBooksSceneView.Coordinator) { self.owner = owner }

    @MainActor @objc func step(_ link: CADisplayLink) { owner?.stepFromLink(link) }
}

extension NativeBooksSceneView.Coordinator {
    @MainActor func stepFromLink(_ link: CADisplayLink) { step(link) }
}
