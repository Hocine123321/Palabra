import CoreMotion
import SceneKit
import simd
import UIKit

/// The Enhancement tier: effects beyond the web scene that never touch the page being read. `EnhancementFlags` decides what is on;
/// this class builds the nodes once and fades them in and out.
@MainActor
final class SceneEnhancements {
    let root = SCNNode()
    private(set) var flags = EnhancementFlags.off

    private let extras = SCNNode()
    private let staticShadows = SCNNode()
    private let glow = SCNNode()
    private let dust = SCNNode()
    private let dustSystem = SCNParticleSystem()
    let window = WindowLight()
    private var bookShadows: [(shadow: SCNNode, book: SCNNode, strength: Double)] = []
    private var shadowAmount = 0.0
    private var glowAmount = 0.0
    private var dustAmount = 0.0
    private var time = 0.0
    private var dustIsDark: Bool?
    private let motion = MotionSway()

    private static let shadowSprite = SoftSprites.radial(UIColor(white: 0, alpha: 0.5), falloff: 0.9)

    init() {
        root.addChildNode(extras)
        root.addChildNode(staticShadows)
        buildGlow()
        buildDust()
        root.addChildNode(window.root)
        extras.isHidden = true
        staticShadows.isHidden = true
    }

    // MARK: Building

    /// A flat soft blob that lies on the desk.
    static func contactShadow(width: Double, length: Double, strength: Double = 1) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(length))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = shadowSprite
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        let blob = SCNNode(geometry: plane)
        plane.materials = [material]
        blob.eulerAngles.x = -.pi / 2
        blob.opacity = CGFloat(strength)
        blob.renderingOrder = -10
        return blob
    }

    /// Soft shadows under the props, and the small extra props (an eraser and a paper clip). `props` is the desk's fading group.
    func install(on desk: DeskNode) {
        desk.props.addChildNode(extras)
        desk.props.addChildNode(staticShadows)
        func shadow(x: Double, z: Double, w: Double, l: Double, rot: Double, strength: Double) {
            let blob = Self.contactShadow(width: w, length: l, strength: strength)
            blob.position = SCNVector3(Float(x), 0.018, Float(z))
            blob.eulerAngles.y = Float(rot)
            staticShadows.addChildNode(blob)
        }
        shadow(x: 1.4, z: -1.65, w: 0.5, l: 0.5, rot: 0.4, strength: 0.9)
        shadow(x: 0.9, z: -1.95, w: 0.95, l: 0.22, rot: -0.35, strength: 0.7)
        shadow(x: -4.6, z: -2.6, w: 1.1, l: 1.1, rot: 0, strength: 0.9)
        shadow(x: 1.45, z: -1.15, w: 0.3, l: 0.2, rot: -0.35, strength: 0.8)
        buildExtras()
    }

    func resetBookShadows() { bookShadows = [] }

    /// Adds the soft shadow under one book (closed, as it lies in the menu).
    func addBookShadow(for book: SCNNode, mirrored: Bool) {
        let w = BookDims.pageWidth, l = BookDims.pageHeight
        let blob = Self.contactShadow(width: w * 1.5, length: l * 1.35)
        blob.position = SCNVector3(Float((mirrored ? -1 : 1) * w * 0.5), 0.018, 0)
        blob.isHidden = true
        book.addChildNode(blob)
        bookShadows.append((blob, book, 0.85))
    }

    private func buildExtras() {
        let eraserMaterial = DeskNode.standard(UIColor(rgb: 0xefc9c0), roughness: 0.95)
        let sleeveMaterial = DeskNode.standard(UIColor(rgb: 0x4a6fa5), roughness: 0.8)
        let eraser = SCNNode()
        let body = SCNNode(geometry: DeskNode.slab(0.17, 0.05, 0.075, 0.012, eraserMaterial))
        let sleeve = SCNNode(geometry: DeskNode.slab(0.07, 0.054, 0.079, 0.012, sleeveMaterial))
        body.position.y = 0.025
        sleeve.position.y = 0.027
        body.castsShadow = true
        eraser.addChildNode(body)
        eraser.addChildNode(sleeve)
        eraser.position = SCNVector3(1.45, 0.016, -1.15)
        eraser.eulerAngles.y = -0.35
        extras.addChildNode(eraser)

        // A paper clip: two thin loops of different size.
        let steel = DeskNode.standard(UIColor(rgb: 0xb9bcc0), roughness: 0.3, metalness: 0.95)
        let clip = SCNNode()
        for (ring, scale, offset) in [(0.05, 1.0, 0.0), (0.034, 1.0, 0.045)] {
            let torus = SCNTorus(ringRadius: CGFloat(ring), pipeRadius: 0.004)
            torus.materials = [steel]
            let node = SCNNode(geometry: torus)
            node.scale = SCNVector3(0.55, 1, Float(scale))
            node.position = SCNVector3(0, 0.005, Float(offset))
            node.castsShadow = true
            clip.addChildNode(node)
        }
        clip.position = SCNVector3(0.85, 0.016, -1.4)
        clip.eulerAngles.y = -0.5
        extras.addChildNode(clip)
    }

    private func buildGlow() {
        let plane = SCNPlane(width: 1.1, height: 1.1)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = SoftSprites.radial(UIColor(rgb: 0xffc070, alpha: 0.85), falloff: 1.4)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.materials = [material]
        glow.geometry = plane
        glow.constraints = [SCNBillboardConstraint()]
        glow.renderingOrder = 5
        glow.opacity = 0
        glow.isHidden = true
        root.addChildNode(glow)
    }

    private func buildDust() {
        let s = dustSystem
        s.birthRate = 0
        s.particleLifeSpan = 16
        s.particleLifeSpanVariation = 5
        let box = SCNBox(width: 3.4, height: 1.3, length: 4, chamferRadius: 0)
        s.emitterShape = box
        s.birthLocation = .volume
        s.particleSize = 0.013
        s.particleSizeVariation = 0.007
        s.particleVelocity = 0.03
        s.particleVelocityVariation = 0.02
        s.spreadingAngle = 180
        s.acceleration = SCNVector3(0.004, 0.003, -0.002)
        s.isAffectedByGravity = false
        s.isLightingEnabled = false
        s.blendMode = .additive
        s.particleImage = SoftSprites.radial(UIColor(white: 1, alpha: 1), size: 32, falloff: 1)
        s.particleColor = UIColor(rgb: 0xfff3dc, alpha: 0.5)
        s.warmupDuration = 6
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.8, 0.8, 0]
        fade.keyTimes = [0, 0.2, 0.8, 1]
        fade.duration = 1
        let controller = SCNParticlePropertyController(animation: fade)
        controller.inputMode = .overLife
        s.propertyControllers = [.opacity: controller]
        dust.position = SCNVector3(0, 0.9, -0.1)
        dust.addParticleSystem(s)
        dust.isHidden = true
        root.addChildNode(dust)
    }

    // MARK: Per frame

    /// `viewing` is true while the menu (or a closed book) shows; effects that sit on the page being read are off otherwise.
    func update(dt: Double, flags new: EnhancementFlags, dark: Bool, menu: Bool, camera: CameraRig, lighting: SceneLighting, bulb: SCNVector3) {
        time += dt
        flags = new
        extras.isHidden = !new.ao
        staticShadows.isHidden = !new.ao

        // Contact shadows under closed books.
        let shadowTarget = new.ao && menu ? 1.0 : 0.0
        shadowAmount += (shadowTarget - shadowAmount) * min(1, dt * 6)
        for entry in bookShadows {
            entry.shadow.isHidden = shadowAmount < 0.02
            entry.shadow.opacity = CGFloat(shadowAmount * entry.strength)
            // The book may be lifted by a hover; the blob stays on the felt.
            entry.shadow.position.y = 0.018 - entry.book.position.y
        }

        // Lamp glow and a slow drift of the lamp's strength.
        let glowTarget = new.bloom ? 1.0 : 0.0
        glowAmount += (glowTarget - glowAmount) * min(1, dt * 3)
        glow.isHidden = glowAmount < 0.02
        glow.position = bulb
        let drift = new.flicker ? 1 + 0.035 * sin(time * 0.43) + 0.02 * sin(time * 1.31 + 1.7) : 1
        glow.opacity = CGFloat(glowAmount * (0.55 + 0.35 * (drift - 0.94) / 0.12))
        glow.scale = SCNVector3(Float(drift), Float(drift), 1)
        lighting.setLampScale(drift)

        // Dust: never while a page is being read.
        let dustTarget = new.dust ? 1.0 : 0.0
        // Gone within a third of a second when reading starts: no mote may drift over a page.
        dustAmount += (dustTarget - dustAmount) * min(1, dt * (new.dust ? 1.5 : 10))
        let hideDust = dustAmount < 0.05
        if hideDust, !dust.isHidden { dustSystem.reset() }
        dust.isHidden = hideDust
        dust.opacity = CGFloat(dustAmount)
        dustSystem.birthRate = new.dust ? 5 : 0
        if dustIsDark != dark {
            dustIsDark = dark
            dustSystem.particleColor = dark ? UIColor(rgb: 0xffc880, alpha: 0.55) : UIColor(rgb: 0xfff3dc, alpha: 0.5)
        }

        // Daylight through the window: light mode, desk only. The bars block the sun only while it shows.
        window.update(dt: dt, target: new.window ? 1 : 0)
        lighting.setWindowAmount(dark ? 0 : window.amount)

        // Depth of field in the menu only.
        camera.setDepthOfField(enabled: new.dof, focusDistance: (camera.pose.look - camera.pose.position).length)

        // The camera leans a little with the phone while the desk is in the menu.
        let wantMotion = new.sway && menu
        motion.setActive(wantMotion)
        camera.setSway(motion.offset(dt: dt, active: wantMotion))
    }
}

private extension SIMD3 where Scalar == Double {
    var length: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Device-motion tilt as a small, smoothed camera offset. Nothing happens where there is no motion hardware (simulator).
@MainActor
final class MotionSway {
    private let manager = CMMotionManager()
    private var running = false
    private var current = SIMD3<Double>.zero

    func setActive(_ on: Bool) {
        guard on != running else { return }
        if on {
            guard manager.isDeviceMotionAvailable else { return }
            manager.deviceMotionUpdateInterval = 1.0 / 30
            manager.startDeviceMotionUpdates()
            running = true
        } else {
            manager.stopDeviceMotionUpdates()
            running = false
        }
    }

    func offset(dt: Double, active: Bool) -> SIMD3<Double> {
        var target = SIMD3<Double>.zero
        if active, running, let g = manager.deviceMotion?.gravity {
            // gravity.x: tilt left/right; gravity.y: how upright the phone is (about -1 when held upright).
            target = SIMD3(max(-1, min(1, g.x)) * 0.16, 0, max(-1, min(1, g.y + 0.7)) * 0.1)
        }
        current += (target - current) * min(1, dt * 3)
        if simd_length(current) < 1e-5 { current = .zero }
        return current
    }
}

/// A light tap when a leaf lands.
@MainActor
enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func leafLanded() {
        generator.impactOccurred(intensity: 0.45)
    }
}
