import SceneKit
import SwiftUI
import UIKit

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
    final class Coordinator: NSObject {
        private weak var view: SCNView?
        private weak var model: BooksSceneModel?
        private weak var controller: BookSceneController?
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0

        func attach(view: SCNView, model: BooksSceneModel, controller: BookSceneController) {
            self.view = view
            self.model = model
            self.controller = controller
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            view.addGestureRecognizer(tap)
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

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let controller, let model, controller.state.mode == .menu else { return }
            if let id = controller.bookID(at: gesture.location(in: view), in: view) {
                model.send(.openBook(id: id, pageID: nil))
            }
        }
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
