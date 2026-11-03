import CoreGraphics
import SceneKit

/// The scene's camera: a pose (position + look-at), the field of view and the projection shift that moves the picture away
/// from the HUD (`_applyCamera` in app.js, which used `PerspectiveCamera.setViewOffset`).
@MainActor
final class CameraRig {
    let node = SCNNode()
    private let camera = SCNCamera()
    private(set) var pose = CameraPose(position: SIMD3(0, 6, 6), look: .zero)
    private(set) var size = CGSize(width: 390, height: 844)
    private(set) var shift = 0.0
    var fovDegrees = 32.0
    /// Extra zoom and screen-space pan from Free view (1 = none).
    private(set) var zoom = 1.0
    private(set) var pan = CGSize.zero
    static let near = 0.05
    static let far = 40.0

    init() {
        camera.zNear = Self.near
        camera.zFar = Self.far
        camera.fieldOfView = CGFloat(fovDegrees)
        node.camera = camera
        apply()
    }

    func setSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        self.size = size
        apply()
    }

    /// `shift` is `(insetTop - insetBottom) / 2` in points (the web scene's view offset).
    func setShift(_ shift: Double) {
        self.shift = shift
        apply()
    }

    func setPose(_ pose: CameraPose) {
        self.pose = pose
        apply()
    }

    func setFree(zoom: Double, pan: CGSize) {
        self.zoom = zoom
        self.pan = pan
        apply()
    }

    /// The projection of `PerspectiveCamera` with a view offset, as a SceneKit matrix.
    static func projection(fovDegrees: Double, size: CGSize, shiftY: Double, shiftX: Double = 0, zoom: Double = 1) -> SCNMatrix4 {
        let near = Self.near, far = Self.far
        let aspect = Double(size.width / size.height)
        var top = near * tan(fovDegrees * .pi / 360) / zoom
        let height = 2 * top
        let width = aspect * height
        var left = -0.5 * width
        left += shiftX * width / Double(size.width)
        top -= shiftY * height / Double(size.height)
        let right = left + width, bottom = top - height
        var m = SCNMatrix4Identity
        m.m11 = Float(2 * near / (right - left))
        m.m22 = Float(2 * near / (top - bottom))
        m.m31 = Float((right + left) / (right - left))
        m.m32 = Float((top + bottom) / (top - bottom))
        m.m33 = Float(-(far + near) / (far - near))
        m.m34 = -1
        m.m43 = Float(-2 * far * near / (far - near))
        m.m44 = 0
        return m
    }

    private func apply() {
        node.position = SCNVector3(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
        node.look(at: SCNVector3(Float(pose.look.x), Float(pose.look.y), Float(pose.look.z)), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        camera.projectionTransform = Self.projection(
            fovDegrees: fovDegrees, size: size, shiftY: shift + Double(pan.height), shiftX: Double(pan.width), zoom: zoom
        )
    }
}
