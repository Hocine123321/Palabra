import SceneKit
import UIKit

/// The room (`Room` in desk.js): a wood desk, a felt mat with a leather edge, paper cut-outs, a lamp, an inkwell and a pencil.
/// `props` holds everything that fades out in Focus Mode.
@MainActor
final class DeskNode {
    let root = SCNNode()
    let props = SCNNode()
    private let woodMaterial = SCNMaterial()
    private let feltMaterial = SCNMaterial()
    private let bulbMaterial = SCNMaterial()
    /// World position of the lamp bulb (for the warm light in dark mode).
    private(set) var bulbPosition = SCNVector3(-4.6 + 0.98 * cos(0.5), 1.55, -2.6 - 0.98 * sin(0.5))

    init() {
        let wood = DeskArt.wood()
        woodMaterial.lightingModel = .physicallyBased
        woodMaterial.diffuse.contents = wood.map
        woodMaterial.roughness.contents = 0.62
        if let normal = NormalMapMaker.make(from: wood.bump, strength: 1.4) { woodMaterial.normal.contents = normal }
        for property in [woodMaterial.diffuse, woodMaterial.normal] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            var t = SCNMatrix4Identity
            t.m11 = 3
            t.m22 = 3.4
            property.contentsTransform = t
            property.mipFilter = .linear
            property.maxAnisotropy = 8
        }
        let top = SCNNode(geometry: Self.slab(18, 0.3, 20, 0.06, woodMaterial))
        top.position = SCNVector3(0, -0.15, -6.1)
        top.castsShadow = true
        root.addChildNode(top)

        feltMaterial.lightingModel = .physicallyBased
        feltMaterial.diffuse.contents = DeskArt.felt()
        feltMaterial.roughness.contents = 1.0
        feltMaterial.diffuse.wrapS = .repeat
        feltMaterial.diffuse.wrapT = .repeat
        var feltT = SCNMatrix4Identity
        feltT.m11 = 6
        feltT.m22 = 6
        feltMaterial.diffuse.contentsTransform = feltT
        let mat = SCNNode(geometry: Self.slab(3.3, 0.016, 4.3, 0.006, feltMaterial))
        mat.position = SCNVector3(0, 0.008, -0.1)
        root.addChildNode(mat)
        let leather = Self.standard(UIColor(rgb: 0x4a3426), roughness: 0.55)
        let edge = SCNNode(geometry: Self.slab(3.34, 0.012, 4.34, 0.005, leather))
        edge.position = SCNVector3(0, 0.004, -0.1)
        root.addChildNode(edge)

        addCutouts()
        addLamp()
        addSmallProps()
        root.addChildNode(props)
        setAppearance(dark: false)
    }

    // MARK: Helpers

    static func standard(_ color: UIColor, roughness: Double, metalness: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static func slab(_ w: Double, _ h: Double, _ l: Double, _ chamfer: Double, _ material: SCNMaterial) -> SCNGeometry {
        let box = SCNBox(width: w, height: h, length: l, chamferRadius: min(chamfer, h / 2 - 0.0005))
        box.chamferSegmentCount = 3
        box.materials = [material]
        return box
    }

    private func cast(_ node: SCNNode) -> SCNNode {
        node.castsShadow = true
        return node
    }

    // MARK: Props

    private func addCutouts() {
        func make(_ path: UIBezierPath, _ color: UInt32, _ x: Double, _ z: Double, _ rot: Double) -> SCNNode {
            let shape = SCNShape(path: path, extrusionDepth: 0.012)
            shape.chamferRadius = 0.003
            shape.chamferMode = .both
            shape.materials = [Self.standard(UIColor(rgb: color), roughness: 0.9)]
            let node = SCNNode(geometry: shape)
            // The shape lies in xy; stand it flat so its extrusion points up.
            node.eulerAngles = SCNVector3(-Float.pi / 2, Float(rot), 0)
            node.position = SCNVector3(Float(x), 0.022, Float(z))
            node.castsShadow = true
            props.addChildNode(node)
            return node
        }
        let circle = UIBezierPath(arcCenter: .zero, radius: 0.42, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        let quarter = UIBezierPath()
        quarter.move(to: .zero)
        quarter.addLine(to: CGPoint(x: 0.7, y: 0))
        quarter.addArc(withCenter: .zero, radius: 0.7, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        quarter.close()
        let s = 0.32, corner = 0.1
        let rounded = UIBezierPath(roundedRect: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s), cornerRadius: corner)
        _ = make(circle, 0xd97757, 1.25, -2.05, 0)
        _ = make(quarter, 0xa3b18a, -1.45, 1.85, 0.4)
        _ = make(rounded, 0x9dbad5, -1.35, -2.25, 0.5)
        let small = make(circle, 0xebb491, 1.2, 2.25, 0)
        small.scale = SCNVector3(0.55, 0.55, 0.55)
    }

    private func addLamp() {
        let lamp = SCNNode()
        let metal = Self.standard(UIColor(rgb: 0x2b2a28), roughness: 0.38, metalness: 0.7)
        let brass = Self.standard(UIColor(rgb: 0xc9992f), roughness: 0.28, metalness: 0.95)
        func cylinder(_ top: Double, _ bottom: Double, _ h: Double, _ m: SCNMaterial) -> SCNNode {
            let c = SCNCone(topRadius: top, bottomRadius: bottom, height: h)
            c.radialSegmentCount = 40
            c.materials = [m]
            return cast(SCNNode(geometry: c))
        }
        let base = cylinder(0.34, 0.4, 0.07, metal)
        base.position.y = 0.035
        let stem = cylinder(0.03, 0.03, 1.25, brass)
        stem.position.y = 0.66
        let arm = cylinder(0.026, 0.026, 1.1, brass)
        arm.position = SCNVector3(0.42, 1.25, 0)
        arm.eulerAngles.z = -1.15
        let joint = SCNSphere(radius: 0.06)
        joint.materials = [brass]
        let jointNode = SCNNode(geometry: joint)
        jointNode.position = SCNVector3(0, 1.28, 0)

        // Open shade: a cone shell, lit from both sides.
        let shadeMaterial = Self.standard(UIColor(rgb: 0x1f5f4a), roughness: 0.4, metalness: 0.2)
        shadeMaterial.isDoubleSided = true
        let shadeMesh = MeshData.lathe(profile: [(r: 0.42, y: -0.21), (r: 0.1, y: 0.21)], segments: 40)
        let shadeGeometry = shadeMesh.geometry()
        shadeGeometry.materials = [shadeMaterial]
        let shade = cast(SCNNode(geometry: shadeGeometry))
        shade.position = SCNVector3(0.98, 1.58, 0)

        bulbMaterial.lightingModel = .physicallyBased
        bulbMaterial.diffuse.contents = UIColor(rgb: 0xfff1c8)
        bulbMaterial.roughness.contents = 0.4
        let bulb = SCNSphere(radius: 0.1)
        bulb.materials = [bulbMaterial]
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.position = SCNVector3(0.98, 1.55, 0)

        for n in [base, stem, arm, jointNode, shade, bulbNode] { lamp.addChildNode(n) }
        lamp.position = SCNVector3(-4.6, 0.016, -2.6)
        lamp.eulerAngles.y = 0.5
        props.addChildNode(lamp)
    }

    private func addSmallProps() {
        // Inkwell
        let ink = SCNNode()
        let glass = Self.standard(UIColor(rgb: 0x1b2a38), roughness: 0.05)
        glass.clearCoat.contents = 1.0
        glass.clearCoatRoughness.contents = 0.05
        let body = cast(SCNNode(geometry: Self.slab(0.22, 0.2, 0.22, 0.04, glass)))
        body.position.y = 0.1
        let capGeometry = SCNCone(topRadius: 0.05, bottomRadius: 0.06, height: 0.05)
        capGeometry.materials = [Self.standard(UIColor(rgb: 0xc9992f), roughness: 0.3, metalness: 0.9)]
        let cap = SCNNode(geometry: capGeometry)
        cap.position.y = 0.225
        ink.addChildNode(body)
        ink.addChildNode(cap)
        ink.position = SCNVector3(1.4, 0.016, -1.65)
        ink.eulerAngles.y = 0.4
        props.addChildNode(ink)

        // Pencil, lying along x.
        let pencil = SCNNode()
        func part(_ geometry: SCNGeometry, _ color: UInt32, _ roughness: Double, x: Double) -> SCNNode {
            geometry.materials = [Self.standard(UIColor(rgb: color), roughness: roughness)]
            let n = SCNNode(geometry: geometry)
            n.eulerAngles.z = .pi / 2
            n.position.x = Float(x)
            n.castsShadow = true
            return n
        }
        let barrel = SCNCylinder(radius: 0.016, height: 0.62)
        barrel.radialSegmentCount = 6
        let tip = SCNCone(topRadius: 0, bottomRadius: 0.016, height: 0.07)
        tip.radialSegmentCount = 6
        let lead = SCNCone(topRadius: 0, bottomRadius: 0.006, height: 0.022)
        lead.radialSegmentCount = 6
        let end = SCNCylinder(radius: 0.0175, height: 0.05)
        end.radialSegmentCount = 6
        // Cones point +y; rotating z by +90 degrees turns +y into -x, so flip these to point along +x.
        let tipNode = part(tip, 0xe8cfa2, 0.8, x: 0.345)
        let leadNode = part(lead, 0x222222, 0.5, x: 0.389)
        tipNode.eulerAngles.z = -.pi / 2
        leadNode.eulerAngles.z = -.pi / 2
        for n in [part(barrel, 0xe9b43c, 0.55, x: 0), tipNode, leadNode, part(end, 0xd97757, 0.6, x: -0.335)] {
            pencil.addChildNode(n)
        }
        pencil.position = SCNVector3(0.9, 0.034, -1.95)
        pencil.eulerAngles.y = -0.35
        props.addChildNode(pencil)
    }

    func setAppearance(dark: Bool) {
        woodMaterial.multiply.contents = dark ? UIColor(rgb: 0x8f6a4a) : UIColor.white
        feltMaterial.multiply.contents = dark ? UIColor(rgb: 0x4d5642) : UIColor(rgb: 0xa3b18a)
        bulbMaterial.emission.contents = dark ? UIColor(rgb: 0xffd48a) : UIColor.black
        bulbMaterial.emission.intensity = dark ? 2.5 : 0
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
