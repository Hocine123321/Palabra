import SceneKit
import UIKit

/// One study tool on the desk: a node with a rest pose and, in use, a pose over the book.
@MainActor
final class ToolNode {
    let name: String
    let root = SCNNode()
    let restPosition: SCNVector3
    let restYaw: Float

    init(name: String, restPosition: SCNVector3, restYaw: Float) {
        self.name = name
        self.restPosition = restPosition
        self.restYaw = restYaw
        root.name = "tool-\(name)"
        root.position = restPosition
        root.eulerAngles = SCNVector3(0, restYaw, 0)
    }

    func add(_ node: SCNNode) { root.addChildNode(node) }

    func isPartOfTool(_ node: SCNNode) -> Bool {
        var n: SCNNode? = node
        while let c = n {
            if c === root { return true }
            n = c.parent
        }
        return false
    }
}

/// The magnifying glass (`Magnifier` in tools.js). The glass shows the open page magnified, everything revealed, along the real
/// view ray; here that is the page bitmap on the disc, with its texture window moved and scaled every frame.
@MainActor
final class LensNode {
    static let radius = 0.27
    static let magnification = 1.9
    let tool = ToolNode(name: "lens", restPosition: SCNVector3(-0.58, 0.05, -1.55), restYaw: 0.55)
    let glass = SCNNode()
    private let restMaterial = SCNMaterial()
    private let magnifyMaterial = SCNMaterial()
    private let sheen = SCNNode()

    init() {
        let r = Self.radius
        let wood = DeskNode.standard(UIColor(rgb: 0x5b3a22), roughness: 0.5)
        let brass = DeskNode.standard(UIColor(rgb: 0xcf9f3a), roughness: 0.25, metalness: 1)
        let darkBrass = DeskNode.standard(UIColor(rgb: 0x8a6420), roughness: 0.4, metalness: 1)

        let profile: [(r: Float, y: Float)] = [(0, 0), (0.034, 0), (0.04, 0.05), (0.05, 0.14), (0.056, 0.26), (0.05, 0.34), (0.04, 0.4), (0.05, 0.43), (0, 0.44)]
        let handleGeometry = MeshData.lathe(profile: profile, segments: 28).geometry()
        handleGeometry.materials = [wood]
        let handle = SCNNode(geometry: handleGeometry)
        handle.eulerAngles.x = .pi / 2 // the lathe stands along y; the handle points along +z
        handle.position = SCNVector3(0, 0, Float(r + 0.1))
        handle.castsShadow = true

        let neckGeometry = SCNCylinder(radius: 0.023, height: 0.14)
        neckGeometry.materials = [brass]
        let neck = SCNNode(geometry: neckGeometry)
        neck.eulerAngles.x = .pi / 2
        neck.position = SCNVector3(0, 0, Float(r + 0.04))
        let ferruleGeometry = SCNCylinder(radius: 0.036, height: 0.05)
        ferruleGeometry.materials = [brass]
        let ferrule = SCNNode(geometry: ferruleGeometry)
        ferrule.eulerAngles.x = .pi / 2
        ferrule.position = SCNVector3(0, 0, Float(r + 0.1))

        let rimGeometry = SCNTorus(ringRadius: r, pipeRadius: 0.02)
        rimGeometry.ringSegmentCount = 64
        rimGeometry.pipeSegmentCount = 16
        rimGeometry.materials = [brass]
        let rim = SCNNode(geometry: rimGeometry)
        rim.castsShadow = true
        let rim2Geometry = SCNTorus(ringRadius: r - 0.018, pipeRadius: 0.007)
        rim2Geometry.materials = [darkBrass]
        let rim2 = SCNNode(geometry: rim2Geometry)

        let glassGeometry = MeshData.disc(radius: Float(r - 0.012), segments: 64).geometry()
        restMaterial.lightingModel = .physicallyBased
        restMaterial.diffuse.contents = UIColor(rgb: 0xcfe6ea)
        restMaterial.transparency = 0.35
        restMaterial.roughness.contents = 0.05
        restMaterial.isDoubleSided = true
        magnifyMaterial.lightingModel = .constant
        magnifyMaterial.isDoubleSided = true
        magnifyMaterial.diffuse.wrapS = .clampToBorder
        magnifyMaterial.diffuse.wrapT = .clampToBorder
        magnifyMaterial.diffuse.borderColor = UIColor(red: 0.93, green: 0.89, blue: 0.80, alpha: 1)
        glassGeometry.materials = [restMaterial]
        glass.geometry = glassGeometry

        let sheenGeometry = MeshData.disc(radius: Float(r - 0.012), segments: 48).geometry()
        let sheenMaterial = SCNMaterial()
        sheenMaterial.lightingModel = .constant
        sheenMaterial.diffuse.contents = UIColor.white
        sheenMaterial.transparency = 0.07
        sheenMaterial.writesToDepthBuffer = false
        sheenMaterial.isDoubleSided = true
        sheenGeometry.materials = [sheenMaterial]
        sheen.geometry = sheenGeometry
        sheen.position.y = 0.002

        for n in [handle, neck, ferrule, rim, rim2, glass, sheen] { tool.add(n) }
    }

    /// Switches the glass between the plain resting disc and the magnifying one.
    func setMagnifying(_ on: Bool) {
        glass.geometry?.materials = [on ? magnifyMaterial : restMaterial]
    }

    func setImage(_ image: CGImage?) {
        magnifyMaterial.diffuse.contents = image ?? UIColor(red: 0.93, green: 0.89, blue: 0.80, alpha: 1)
    }

    func setTone(_ tone: Double) {
        magnifyMaterial.multiply.contents = UIColor(white: CGFloat(tone), alpha: 1)
    }

    /// Where on the page bitmap the glass looks: its window is `2R / (mag * page)` wide, centred on page point (u0, v0).
    func setWindow(u0: Double, v0: Double) {
        let sx = 2 * Self.radius / (Self.magnification * BookDims.pageWidth)
        let sy = 2 * Self.radius / (Self.magnification * BookDims.pageHeight)
        var t = SCNMatrix4Identity
        t.m11 = Float(sx)
        t.m22 = Float(sy)
        t.m41 = Float(u0 - 0.5 * sx)
        t.m42 = Float(v0 - 0.5 * sy)
        magnifyMaterial.diffuse.contentsTransform = t
    }
}

enum ToolFactory {
    @MainActor
    static func bookmark() -> ToolNode {
        let tool = ToolNode(name: "bookmark", restPosition: SCNVector3(0.12, 0.016, -1.5), restYaw: -0.35)
        func box(_ w: Double, _ h: Double, _ l: Double, _ m: SCNMaterial) -> SCNNode {
            let g = SCNBox(width: w, height: h, length: l, chamferRadius: 0)
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.castsShadow = true
            return n
        }
        let gold = DeskNode.standard(UIColor(rgb: 0xe4b44f), roughness: 0.3, metalness: 0.9)
        let card = box(0.15, 0.006, 0.48, DeskNode.standard(UIColor(rgb: 0xd97757), roughness: 0.7))
        card.position.y = 0.003
        let stripe = box(0.1, 0.0015, 0.012, gold)
        stripe.position = SCNVector3(0, 0.0068, -0.15)
        let stripe2 = box(0.1, 0.0015, 0.012, gold)
        stripe2.position = SCNVector3(0, 0.0068, -0.12)
        let holeGeometry = SCNCylinder(radius: 0.016, height: 0.0075)
        holeGeometry.materials = [DeskNode.standard(UIColor(rgb: 0x1b1a18), roughness: 0.9)]
        let hole = SCNNode(geometry: holeGeometry)
        hole.position = SCNVector3(0, 0.0035, 0.19)
        let cordGeometry = SCNCylinder(radius: 0.004, height: 0.2)
        cordGeometry.materials = [DeskNode.standard(UIColor(rgb: 0xe4b44f), roughness: 0.8)]
        let cord = SCNNode(geometry: cordGeometry)
        cord.eulerAngles.x = .pi / 2
        cord.position = SCNVector3(0, 0.004, 0.31)
        let tasselGeometry = SCNCone(topRadius: 0, bottomRadius: 0.022, height: 0.1)
        tasselGeometry.materials = [DeskNode.standard(UIColor(rgb: 0xe4b44f), roughness: 0.8)]
        let tassel = SCNNode(geometry: tasselGeometry)
        tassel.eulerAngles.x = -.pi / 2 // the cone's tip points along -y; this points the wide end away from the card
        tassel.position = SCNVector3(0, 0.004, 0.46)
        for n in [card, stripe, stripe2, hole, cord, tassel] { tool.add(n) }
        return tool
    }

    static let rulerLength = 1.12
    static let rulerWidth = 0.15

    @MainActor
    static func ruler() -> ToolNode {
        let tool = ToolNode(name: "ruler", restPosition: SCNVector3(0.55, 0.016, -1.2), restYaw: 0.12)
        let L = rulerLength, W = rulerWidth
        let bodyMaterial = DeskNode.standard(UIColor(rgb: 0xf2b68f), roughness: 0.15)
        bodyMaterial.transparency = 0.55
        bodyMaterial.isDoubleSided = true
        bodyMaterial.writesToDepthBuffer = false
        bodyMaterial.clearCoat.contents = 1.0
        let bodyGeometry = SCNBox(width: L, height: 0.012, length: W, chamferRadius: 0)
        bodyGeometry.materials = [bodyMaterial]
        let body = SCNNode(geometry: bodyGeometry)
        body.position.y = 0.006
        let edgeGeometry = SCNBox(width: L, height: 0.016, length: 0.01, chamferRadius: 0)
        edgeGeometry.materials = [DeskNode.standard(UIColor(rgb: 0xd97757), roughness: 0.4)]
        let edge = SCNNode(geometry: edgeGeometry)
        edge.position = SCNVector3(0, 0.008, Float(W / 2))
        tool.add(body)
        tool.add(edge)
        let tick = DeskNode.standard(UIColor(rgb: 0x3b2418), roughness: 0.8)
        for i in 0...28 {
            let long = i % 5 == 0
            let g = SCNBox(width: 0.003, height: 0.0016, length: long ? 0.04 : 0.022, chamferRadius: 0)
            g.materials = [tick]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(-L / 2 + 0.03 + Double(i) * (L - 0.06) / 28), 0.0128, Float(W / 2 - (long ? 0.03 : 0.02)))
            tool.add(n)
        }
        return tool
    }
}
