import CoreGraphics
import Foundation
import SceneKit
import UIKit

/// How far along the open cover and the pages are, as the nodes see them. Pure data on top of `BookShape`.
struct BookStyle {
    var subject: String
    var rtl: Bool
    var leafCount: Int
    var bulk: Double

    static func bulk(for subject: String) -> Double { subject == "geography" ? 0.18 : 0.26 }
}

/// One 3D book (`Book3D` in book3d.js): hinged cover boards, a spine, page blocks, bending leaves and a ribbon.
///
/// A right-to-left book is built mirrored (x negated, winding reversed) instead of with a negative node scale, which keeps
/// culling and lighting predictable. Page images keep their normal orientation: the u texture coordinate of a mirrored
/// book is flipped the same way the web scene flipped its texture.
@MainActor
final class BookNode {
    let root = SCNNode()
    let style: BookStyle
    private(set) var shape: BookShape
    private let sign: Float
    private let covers: CoverTextures

    private let pivot = SCNNode()
    private let frontCover = SCNNode()
    private let backCover = SCNNode()
    private let spine = SCNNode()
    private var bands: [SCNNode] = []
    private let blockNodes = [SCNNode(), SCNNode()]
    private let ribbon = SCNNode()
    private var frontLeaf: [SCNNode] = []
    private var backLeaf: [SCNNode] = []
    private var frontMaterial: [SCNMaterial] = []
    private var backMaterial: [SCNMaterial] = []
    private let blockMaterial = SCNMaterial()
    private let ribbonMaterial = SCNMaterial()
    private var dirty = Set<Int>()
    private var layoutDirty = true
    private let spineRadius: Double
    /// Gutter dip factor (1 = the web scene's look; reading poses lower it).
    var gutterScale = 1.0 { didSet { if gutterScale != oldValue { markAllDirty() } } }

    static let blankPaper = UIColor(red: 0xf0 / 255.0, green: 0xe6 / 255.0, blue: 0xcd / 255.0, alpha: 1)

    init(style: BookStyle, covers: CoverTextures, pageEdge: CGImage) {
        self.style = style
        self.covers = covers
        sign = style.rtl ? -1 : 1
        shape = BookShape(leafCount: style.leafCount, bulk: style.bulk)
        spineRadius = (BookDims.coverThickness * 2 + style.bulk) / 2
        build(pageEdge: pageEdge)
        markAllDirty()
        layout()
    }

    var leafCount: Int { shape.leafCount }

    // MARK: Materials

    private func pbr(color: Any, roughness: Double, metalness: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private func tiled(_ material: SCNMaterial, x: Float, y: Float) {
        var t = SCNMatrix4Identity
        t.m11 = x
        t.m22 = y
        material.diffuse.contentsTransform = t
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
    }

    private func cloth() -> SCNMaterial { pbr(color: UIColor(pageColor: covers.cloth), roughness: 0.85) }

    private func endpaper() -> SCNMaterial {
        let m = pbr(color: covers.endpaper, roughness: 0.9)
        tiled(m, x: 2, y: 3)
        return m
    }

    private func outerFront() -> SCNMaterial {
        let m = pbr(color: covers.color, roughness: 1, metalness: 1)
        m.roughness.contents = covers.roughness
        m.metalness.contents = covers.metalness
        if let normal = NormalMapMaker.make(from: covers.bump, strength: 1.6) { m.normal.contents = normal }
        for property in [m.diffuse, m.roughness, m.metalness, m.normal] {
            property.mipFilter = .linear
            property.maxAnisotropy = 8
        }
        return m
    }

    private func box(width: Double, height: Double, length: Double, top: SCNMaterial, bottom: SCNMaterial) -> SCNNode {
        let mesh = MeshData.box(width: Float(width), height: Float(height), length: Float(length))
        let geometry = mesh.geometry()
        geometry.materials = [cloth(), top, bottom]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = true
        return node
    }

    // MARK: Build

    private func build(pageEdge: CGImage) {
        let w = BookDims.pageWidth + BookDims.overhangX
        let l = BookDims.pageHeight + BookDims.overhangZ * 2
        let t = BookDims.coverThickness
        // Back cover: endpaper up, cloth down.
        let back = box(width: w, height: t, length: l, top: endpaper(), bottom: pbr(color: UIColor(pageColor: covers.cloth), roughness: 0.8))
        backCover.addChildNode(back)
        backCover.position = SCNVector3(Float(w / 2) * sign, Float(t / 2), 0)
        root.addChildNode(backCover)
        // Front cover on a pivot at the spine: art up, endpaper down (it faces up once the cover has turned over).
        let front = box(width: w, height: t, length: l, top: outerFront(), bottom: endpaper())
        frontCover.addChildNode(front)
        frontCover.position = SCNVector3(Float(w / 2) * sign, Float(t / 2), 0)
        pivot.addChildNode(frontCover)
        root.addChildNode(pivot)

        // Spine: a half pipe wrapping the binding, with raised bands (history) or two bands around a label (atlas).
        let pipe = MeshData.halfPipe(radius: Float(spineRadius), length: Float(l), steps: 28)
        let spineMaterial = pbr(color: UIColor(pageColor: covers.cloth), roughness: 0.55)
        spineMaterial.isDoubleSided = true
        spine.geometry = (sign < 0 ? pipe.mirroredInX() : pipe).geometry()
        spine.geometry?.materials = [spineMaterial]
        spine.castsShadow = true
        root.addChildNode(spine)
        let gold = pbr(color: UIColor(red: 0xc9 / 255.0, green: 0x99 / 255.0, blue: 0x2f / 255.0, alpha: 1), roughness: 0.3, metalness: 0.9)
        gold.isDoubleSided = true
        let bandCount = style.subject == "geography" ? 2 : 4
        for i in 0..<bandCount {
            let z = (-0.42 + Double(i) * (0.84 / Double(max(1, bandCount - 1)))) * BookDims.pageHeight
            var arc = MeshData.tubeArc(radius: Float(spineRadius) + 0.004, tube: 0.006, from: Float.pi / 2, to: 3 * Float.pi / 2, arcSteps: 24, tubeSteps: 6)
            if sign < 0 { arc = arc.mirroredInX() }
            let node = SCNNode(geometry: arc.geometry())
            node.geometry?.materials = [gold]
            node.position = SCNVector3(0, Float(spineRadius), Float(z))
            root.addChildNode(node)
            bands.append(node)
        }

        // Page blocks.
        blockMaterial.lightingModel = .physicallyBased
        blockMaterial.diffuse.contents = pageEdge
        blockMaterial.roughness.contents = 0.95
        blockMaterial.isDoubleSided = true
        blockMaterial.diffuse.wrapS = .repeat
        blockMaterial.diffuse.wrapT = .repeat
        for node in blockNodes {
            node.castsShadow = true
            root.addChildNode(node)
        }

        // Leaves: a front mesh (faces up) and a back mesh (faces down) sharing one bent sheet.
        for _ in 0..<shape.leafCount {
            let f = pbr(color: Self.blankPaper, roughness: 0.92)
            let b = pbr(color: Self.blankPaper, roughness: 0.92)
            // Front shows the up-facing side; the back mesh is the same triangles seen from below.
            f.cullMode = .back
            b.cullMode = .front
            for m in [f, b] { Self.installBandModifier(m) }
            frontMaterial.append(f)
            backMaterial.append(b)
            let fn = SCNNode(), bn = SCNNode()
            for node in [fn, bn] {
                node.castsShadow = true
                root.addChildNode(node)
            }
            frontLeaf.append(fn)
            backLeaf.append(bn)
        }
        // Ribbon.
        ribbonMaterial.lightingModel = .physicallyBased
        ribbonMaterial.diffuse.contents = style.subject == "geography"
            ? UIColor(red: 0xc9 / 255.0, green: 0x74 / 255.0, blue: 0x2a / 255.0, alpha: 1)
            : UIColor(red: 0x8c / 255.0, green: 0x1f / 255.0, blue: 0x2c / 255.0, alpha: 1)
        ribbonMaterial.roughness.contents = 0.55
        ribbonMaterial.isDoubleSided = true
        ribbon.castsShadow = true
        root.addChildNode(ribbon)
    }

    /// The ruler's dimming band over a page (`uBand`: x on/off, y centre v in image space, z half height).
    static func installBandModifier(_ material: SCNMaterial) {
        material.shaderModifiers = [.surface: """
        #pragma arguments
        float4 band;
        #pragma body
        if (band.x > 0.5) {
            float d = abs(_surface.diffuseTexcoord.y - band.y);
            float inBand = 1.0 - smoothstep(band.z, band.z + 0.012, d);
            _surface.diffuse.rgb *= mix(0.42, 1.0, inBand);
        }
        """]
        material.setValue(SCNVector4(0, 0, 0, 0), forKey: "band")
    }

    static func leafUVs(back: Bool, rtl: Bool) -> [SIMD2<Float>] {
        BookShape.leafUVs(back: back).map { uv in
            // A mirrored book flips u so the bitmap keeps its orientation; SceneKit's v runs top to bottom.
            SIMD2<Float>(rtl ? 1 - uv.x : uv.x, 1 - uv.y)
        }
    }

    // MARK: Picking

    /// Which leaf face a node of this book is (nil for any other node).
    func face(of node: SCNNode) -> (leaf: Int, front: Bool)? {
        if let i = frontLeaf.firstIndex(where: { $0 === node }) { return (i, true) }
        if let i = backLeaf.firstIndex(where: { $0 === node }) { return (i, false) }
        return nil
    }

    // MARK: State

    func setLeafProgress(_ index: Int, _ p: Double) {
        guard shape.leaves.indices.contains(index), shape.leaves[index].p != p else { return }
        shape.leaves[index].p = p
        dirty.insert(index)
        layoutDirty = true
    }

    func setPeek(_ index: Int, _ peek: Double) {
        guard shape.leaves.indices.contains(index), abs(shape.leaves[index].peek - peek) > 1e-4 else { return }
        shape.leaves[index].peek = peek
        dirty.insert(index)
    }

    func setGrab(_ index: Int, _ z: Double) {
        guard shape.leaves.indices.contains(index) else { return }
        shape.leaves[index].grabZ = z
    }

    func setCoverOpen(_ p: Double) {
        shape.coverOpen = p
        // A leaf's shape does not depend on how far the cover is open (`BookShape.deform` never reads `coverOpen`), so the
        // leaves are NOT rebuilt here. This used to dirty every leaf, which allocated two new meshes per leaf on every frame
        // of the open and close animation and made the camera move stutter.
        layout()
    }

    func surfaceY(side: Int) -> Double { shape.surfaceY(side: side) }

    /// Number of leaves lying on the left stack (turned past the halfway point).
    var turnedCount: Int { shape.leaves.filter { $0.p >= 0.5 }.count }

    var hasDirtyLeaves: Bool { !dirty.isEmpty }

    private func markAllDirty() {
        dirty = Set(0..<shape.leafCount)
        layoutDirty = true
    }

    func leafProgress(_ index: Int) -> Double { shape.leaves[index].p }
    func peek(_ index: Int) -> Double { shape.leaves[index].peek }

    // MARK: Images

    /// The bitmap shown on a leaf face (nil = blank paper).
    func setLeafImage(_ index: Int, front isFront: Bool, image: CGImage?) {
        guard frontMaterial.indices.contains(index) else { return }
        let m = isFront ? frontMaterial[index] : backMaterial[index]
        if let image {
            m.diffuse.contents = image
            m.diffuse.mipFilter = .linear
            m.diffuse.minificationFilter = .linear
            m.diffuse.magnificationFilter = .linear
            m.diffuse.maxAnisotropy = 8
        } else {
            m.diffuse.contents = Self.blankPaper
        }
    }

    /// The dimming band of the ruler on one face (centre in web v, 1 at the head), or nil to switch it off everywhere.
    func setBand(face: (leaf: Int, front: Bool)?, centreV: Double, halfV: Double) {
        for m in frontMaterial + backMaterial { m.setValue(SCNVector4(0, 0, 0, 0), forKey: "band") }
        guard let face, frontMaterial.indices.contains(face.leaf) else { return }
        let m = face.front ? frontMaterial[face.leaf] : backMaterial[face.leaf]
        m.setValue(SCNVector4(1, Float(1 - centreV), Float(halfV), 0), forKey: "band")
    }

    // MARK: Layout

    private func smooth(_ x: Double) -> Double { BookMath.smooth(0, 1, x) }

    /// Re-poses the cover, spine, blocks, ribbon and every leaf whose shape changed.
    func layout() {
        let open = shape.coverOpen
        let heights = shape.blockHeights()
        for (i, side) in [1, -1].enumerated() {
            placeBlock(node: blockNodes[i], height: i == 0 ? heights.right : heights.left, side: side)
        }
        let closedY = BookDims.coverThickness + shape.bulk
        pivot.position = SCNVector3(0, Float(BookMath.lerp(closedY, BookDims.coverThickness, smooth(open))), 0)
        pivot.eulerAngles = SCNVector3(0, 0, Float(open * Double.pi) * sign)
        let fold = smooth(open)
        let sx = Float(BookMath.lerp(1, 0.35, fold)), sy = Float(BookMath.lerp(1, 0.1, fold))
        let y = Float(spineRadius * BookMath.lerp(1, 0.1, fold))
        spine.scale = SCNVector3(sx, sy, 1)
        spine.position = SCNVector3(0, y, 0)
        for band in bands {
            band.scale = SCNVector3(sx, sy, 1)
            band.position.y = y
        }
        for index in shape.leaves.indices where dirty.contains(index) || layoutDirty { deform(index) }
        dirty.removeAll()
        layoutDirty = false
        layoutRibbon()
    }

    private func placeBlock(node: SCNNode, height: Double, side: Int) {
        let block = shape.block(height: height, side: side)
        node.isHidden = !block.visible
        guard block.visible else { return }
        // Fixed normals: foot faces +z, head faces -z, the fore edge faces +x.
        var normals = [SIMD3<Float>](repeating: .zero, count: BookDims.blockVertexCount)
        for i in 0..<BookShape.blockHeadBase { normals[BookShape.blockFootBase + i] = SIMD3(0, 0, 1) }
        for i in 0..<(BookShape.blockForeBase - BookShape.blockHeadBase) { normals[BookShape.blockHeadBase + i] = SIMD3(0, 0, -1) }
        for i in 0..<4 { normals[BookShape.blockForeBase + i] = SIMD3(1, 0, 0) }
        var mesh = MeshData()
        mesh.positions = block.positions
        mesh.normals = normals
        mesh.uvs = block.uvs.map { SIMD2($0.x, $0.y) }
        mesh.elements = [BookShape.blockIndices]
        // The left stack (side -1) and a mirrored book each flip x.
        let flip = Float(side) * sign
        if flip < 0 { mesh = mesh.mirroredInX() }
        let geometry = mesh.geometry()
        geometry.materials = [blockMaterial]
        node.geometry = geometry
        node.position = SCNVector3(0, Float(BookDims.coverThickness), 0)
    }

    private func deform(_ index: Int) {
        let leaf = shape.deform(leaf: index, gutterScale: gutterScale)
        var positions = leaf.positions
        var normals = leaf.normals
        var indices = BookShape.leafIndices
        if sign < 0 {
            positions = positions.map { SIMD3(-$0.x, $0.y, $0.z) }
            normals = normals.map { SIMD3(-$0.x, $0.y, $0.z) }
            indices = MeshData.reversedWinding(indices)
        }
        var front = MeshData()
        front.positions = positions
        front.normals = normals
        front.uvs = Self.frontUVForRTL(style.rtl)
        front.elements = [indices]
        var back = front
        back.normals = normals.map { -$0 }
        back.uvs = Self.backUVForRTL(style.rtl)
        let fg = front.geometry()
        fg.materials = [frontMaterial[index]]
        frontLeaf[index].geometry = fg
        let bg = back.geometry()
        bg.materials = [backMaterial[index]]
        backLeaf[index].geometry = bg
    }

    private static let frontUVLTR = leafUVs(back: false, rtl: false)
    private static let frontUVRTL = leafUVs(back: false, rtl: true)
    private static func frontUVForRTL(_ rtl: Bool) -> [SIMD2<Float>] { rtl ? frontUVRTL : frontUVLTR }
    private static let backUVLTR = leafUVs(back: true, rtl: false)
    private static let backUVRTL = leafUVs(back: true, rtl: true)
    private static func backUVForRTL(_ rtl: Bool) -> [SIMD2<Float>] { rtl ? backUVRTL : backUVLTR }

    // MARK: Ribbon sway (Enhancement tier)

    private var ribbonSway: Float = 0
    private var ribbonVelocity: Float = 0
    private var lastLeafSum = 0.0
    private var lastRootX: Float = 0

    /// The ribbon's loose end swings when leaves turn or the book moves, and settles (a damped spring).
    func stepRibbon(dt: Double, enabled: Bool) {
        let sum = (0..<leafCount).reduce(0.0) { $0 + leafProgress($1) }
        let x = root.position.x
        if enabled {
            ribbonVelocity += Float(sum - lastLeafSum) * 0.35 * sign
            ribbonVelocity -= (x - lastRootX) * 0.8
        }
        lastLeafSum = sum
        lastRootX = x
        guard abs(ribbonSway) > 1e-4 || abs(ribbonVelocity) > 1e-4 else { return }
        let h = Float(min(dt, 1.0 / 30))
        ribbonVelocity += (-60 * ribbonSway - 4.5 * ribbonVelocity) * h
        ribbonSway = max(-0.06, min(0.06, ribbonSway + ribbonVelocity * h))
        if !enabled, abs(ribbonSway) < 2e-4, abs(ribbonVelocity) < 2e-3 {
            ribbonSway = 0
            ribbonVelocity = 0
        }
        layoutRibbon()
    }

    private func layoutRibbon() {
        let r = shape.ribbon()
        ribbon.isHidden = !r.visible
        guard r.visible else { return }
        var mesh = MeshData()
        mesh.positions = r.positions
        if ribbonSway != 0 {
            let hang = Float(BookDims.pageHeight / 2)
            for i in mesh.positions.indices {
                let over = max(0, mesh.positions[i].z - hang)
                mesh.positions[i].x += ribbonSway * min(1, over / 0.16)
            }
        }
        let rows = BookDims.ribbonRows
        var indices: [UInt32] = []
        for row in 0..<(rows - 1) {
            let a = UInt32(row * 2)
            indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        mesh.elements = [indices]
        mesh.normals = BookShape.vertexNormals(positions: mesh.positions, indices: indices)
        mesh.uvs = [SIMD2<Float>](repeating: .zero, count: mesh.positions.count)
        if sign < 0 { mesh = mesh.mirroredInX() }
        let geometry = mesh.geometry()
        geometry.materials = [ribbonMaterial]
        ribbon.geometry = geometry
    }
}

extension UIColor {
    convenience init(pageColor c: PageColor) {
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
