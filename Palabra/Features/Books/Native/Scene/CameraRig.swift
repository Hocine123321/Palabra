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
    /// Extra zoom and screen-space pan from Free view (1 = none); the pan is how far the picture moved, in points, y down.
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

    /// The near-plane window of `PerspectiveCamera` with a view offset (left, right, top, bottom).
    static func frustum(fovDegrees: Double, size: CGSize, shiftY: Double, shiftX: Double = 0, zoom: Double = 1)
        -> (left: Double, right: Double, top: Double, bottom: Double) {
        let aspect = Double(size.width / size.height)
        var top = near * tan(fovDegrees * .pi / 360) / zoom
        let height = 2 * top
        let width = aspect * height
        var left = -0.5 * width
        left += shiftX * width / Double(size.width)
        top -= shiftY * height / Double(size.height)
        return (left, left + width, top, top - height)
    }

    /// The projection of `PerspectiveCamera` with a view offset, as a SceneKit matrix.
    static func projection(fovDegrees: Double, size: CGSize, shiftY: Double, shiftX: Double = 0, zoom: Double = 1) -> SCNMatrix4 {
        let f = frustum(fovDegrees: fovDegrees, size: size, shiftY: shiftY, shiftX: shiftX, zoom: zoom)
        let near = Self.near, far = Self.far
        var m = SCNMatrix4Identity
        m.m11 = Float(2 * near / (f.right - f.left))
        m.m22 = Float(2 * near / (f.top - f.bottom))
        m.m31 = Float((f.right + f.left) / (f.right - f.left))
        m.m32 = Float((f.top + f.bottom) / (f.top - f.bottom))
        m.m33 = Float(-(far + near) / (far - near))
        m.m34 = -1
        m.m43 = Float(-2 * far * near / (far - near))
        m.m44 = 0
        return m
    }

    /// The world-space ray through a point of the view (points, y down), for picking without a renderer.
    func ray(through point: CGPoint) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        let f = Self.frustum(fovDegrees: fovDegrees, size: size, shiftY: shift - Double(pan.height), shiftX: -Double(pan.width), zoom: zoom)
        let nx = Double(point.x / size.width), ny = Double(point.y / size.height)
        let x = f.left + nx * (f.right - f.left)
        let y = f.top - ny * (f.top - f.bottom)
        // Camera basis: forward toward the look point, right = forward x up, up = right x forward.
        let forward = Self.normalized(pose.look - pose.position)
        let right = Self.normalized(Self.cross(forward, SIMD3(0, 1, 0)))
        let up = Self.cross(right, forward)
        let direction = Self.normalized(right * x + up * y + forward * Self.near)
        return (pose.position, direction)
    }

    /// Where a world point lands in the view (points, y down), or nil when it is behind the camera.
    func screenPoint(for world: SIMD3<Double>) -> CGPoint? {
        let f = Self.frustum(fovDegrees: fovDegrees, size: size, shiftY: shift - Double(pan.height), shiftX: -Double(pan.width), zoom: zoom)
        let forward = Self.normalized(pose.look - pose.position)
        let right = Self.normalized(Self.cross(forward, SIMD3(0, 1, 0)))
        let up = Self.cross(right, forward)
        let d = world - pose.position
        let depth = d.x * forward.x + d.y * forward.y + d.z * forward.z
        guard depth > 1e-6 else { return nil }
        let xn = (d.x * right.x + d.y * right.y + d.z * right.z) * Self.near / depth
        let yn = (d.x * up.x + d.y * up.y + d.z * up.z) * Self.near / depth
        let nx = (xn - f.left) / (f.right - f.left)
        let ny = (f.top - yn) / (f.top - f.bottom)
        return CGPoint(x: nx * Double(size.width), y: ny * Double(size.height))
    }

    /// Where the view ray meets the horizontal plane at height `y`, or nil when it never does.
    func planePoint(through point: CGPoint, y: Double) -> SIMD3<Double>? {
        let r = ray(through: point)
        guard abs(r.direction.y) > 1e-9 else { return nil }
        let t = (y - r.origin.y) / r.direction.y
        guard t > 0 else { return nil }
        return r.origin + r.direction * t
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func normalized(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let l = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        return l == 0 ? v : v / l
    }

    private func apply() {
        node.position = SCNVector3(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
        node.look(at: SCNVector3(Float(pose.look.x), Float(pose.look.y), Float(pose.look.z)), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        camera.projectionTransform = Self.projection(
            fovDegrees: fovDegrees, size: size, shiftY: shift - Double(pan.height), shiftX: -Double(pan.width), zoom: zoom
        )
    }
}
