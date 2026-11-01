import Foundation

/// Dimensions and counts copied from `web/books3d/src/book3d.js`. World units are the Three.js ones.
enum BookDims {
    static let pageWidth = 1.0
    /// `PAGE_H / PAGE_W * PW` with the 1280 x 1820 page bitmap.
    static let pageHeight = 1820.0 / 1280.0
    static let coverThickness = 0.04
    static let overhangX = 0.035
    static let overhangZ = 0.045
    /// Leaf grid: 28 x 8 cells, so 29 x 9 vertices.
    static let leafCellsX = 28
    static let leafCellsZ = 8
    static let blockColumns = 14
    static let gutterDip = 0.03
    static let verticesPerLeaf = (leafCellsX + 1) * (leafCellsZ + 1)
    static let blockVertexCount = (blockColumns + 1) * 2 * 2 + 4
    static let ribbonRows = 13
}

/// What the person or an animation is doing to one leaf.
struct LeafState: Equatable {
    /// 0 = lying on the right stack, 1 = lying on the left stack.
    var p: Double = 0
    /// Hover lift of the outer corner, 0...1.
    var peek: Double = 0
    /// Where along the page height the leaf is held (0 = head, 1 = foot).
    var grabZ: Double = 0.5
}

struct LeafMesh: Equatable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
}

/// The paper block under the leaves on one side of the binding.
struct BlockMesh: Equatable {
    var visible: Bool
    /// `-1` for the left stack (mirrored), `1` otherwise.
    var scaleX: Double
    var positions: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]
}

/// The geometry maths of one book (`Book3D` in book3d.js) with no SceneKit in it, so it can be tested against the numbers the
/// JS produces. Logical layout is left to right (spine at x = 0, right page at x > 0); a right-to-left book is the same model
/// mirrored by the node that draws it.
struct BookShape {
    let leafCount: Int
    let bulk: Double
    var leaves: [LeafState]
    /// 0 = closed, 1 = open.
    var coverOpen: Double = 0

    init(leafCount: Int, bulk: Double = 0.22) {
        self.leafCount = max(1, leafCount)
        self.bulk = bulk
        self.leaves = Array(repeating: LeafState(), count: max(1, leafCount))
    }

    // MARK: Heights

    /// Height of the top surface of leaf `i` when resting on the right / left stack, given the other leaves' progress.
    func restY(_ i: Int) -> (yr: Double, yl: Double) {
        var right = 0.0, left = 0.0
        for j in 0..<leafCount {
            let pj = leaves[j].p
            if j >= i { right += 1 - pj }
            if j <= i { left += pj }
        }
        let k = bulk / Double(leafCount)
        return (BookDims.coverThickness + k * right, BookDims.coverThickness + k * left)
    }

    /// World-space height of the page surface for a face (`side` > 0 = right stack) near the outer area.
    func surfaceY(side: Int) -> Double {
        let k = bulk / Double(leafCount)
        var r = 0.0, l = 0.0
        for leaf in leaves { r += 1 - leaf.p; l += leaf.p }
        return BookDims.coverThickness + k * (side > 0 ? r : l) + 0.0007 * Double(leafCount) + 0.001
    }

    /// Heights of the two page blocks (right, left).
    func blockHeights() -> (right: Double, left: Double) {
        let k = bulk / Double(leafCount)
        var sumR = 0.0, sumL = 0.0
        for leaf in leaves { sumR += 1 - leaf.p; sumL += leaf.p }
        return (k * sumR, k * sumL)
    }

    // MARK: Leaves

    /// Triangle indices of a leaf grid, counter-clockwise seen from +y with +z toward the viewer.
    static let leafIndices: [UInt32] = {
        let nx = BookDims.leafCellsX + 1
        var out: [UInt32] = []
        out.reserveCapacity(BookDims.leafCellsX * BookDims.leafCellsZ * 6)
        for iz in 0..<BookDims.leafCellsZ {
            for ix in 0..<BookDims.leafCellsX {
                let a = UInt32(iz * nx + ix), b = a + 1, c = a + UInt32(nx), d = c + 1
                out.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return out
    }()

    /// Texture coordinates of a leaf face. The back face is the front mirrored in u.
    static func leafUVs(back: Bool) -> [SIMD2<Float>] {
        let nx = BookDims.leafCellsX + 1, nz = BookDims.leafCellsZ + 1
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(nx * nz)
        for iz in 0..<nz {
            for ix in 0..<nx {
                let u = Double(ix) / Double(BookDims.leafCellsX)
                let v = 1 - Double(iz) / Double(BookDims.leafCellsZ)
                out.append(SIMD2<Float>(Float(back ? 1 - u : u), Float(v)))
            }
        }
        return out
    }

    /// The bent sheet of leaf `index`: lies flat on a stack, curls around the binding while it turns, dips into the gutter.
    /// `gutterScale` is 1 for the original look; reading poses ease it (see the readability design).
    func deform(leaf index: Int, gutterScale: Double = 1) -> LeafMesh {
        let leaf = leaves[index]
        let p = leaf.p, peek = leaf.peek, grabZ = leaf.grabZ
        let rest = restY(index)
        let eps = 0.0007 * Double(index + 1)
        let yRoot = BookMath.lerp(rest.yr, rest.yl, p) + eps
        let nx = BookDims.leafCellsX + 1, nz = BookDims.leafCellsZ + 1
        let phiRoot = p * Double.pi
        let lagAmp = 0.55 * sin(2 * Double.pi * p) * (p > 0 && p < 1 ? 1 : 0)
        let flight = sin(Double.pi * p)
        let ds = BookDims.pageWidth / Double(BookDims.leafCellsX)
        var positions = [SIMD3<Float>](repeating: .zero, count: nx * nz)
        for iz in 0..<nz {
            let zn = Double(iz) / Double(BookDims.leafCellsZ)
            let z = (zn - 0.5) * BookDims.pageHeight
            let grab = 1 + 0.9 * (1 - abs(zn - grabZ) * 1.4)
            var x = 0.0
            var y = yRoot
            for ix in 0..<nx {
                let s = Double(ix) / Double(BookDims.leafCellsX)
                // Resting leaves dip into the binding and rise toward the fore edge.
                let dip = -BookDims.gutterDip * gutterScale * (1 - BookMath.smooth(0, 0.42, s)) * (1 - flight)
                var yy = y + dip
                let xx = x
                // Hover: lift the corner nearest the pointer (only on a leaf lying on the right stack).
                if peek > 0 {
                    yy += peek * 0.2 * BookMath.smooth(0.5, 1, s) * BookMath.smooth(0.15, 1, 1 - abs(zn - grabZ) * 1.2) * (p == 0 ? 1 : 0)
                }
                positions[iz * nx + ix] = SIMD3<Float>(Float(xx), Float(yy), Float(z))
                // Advance along the sheet.
                let peekBend = (peek > 0 && p == 0) ? -peek * 0.9 * s : 0
                let phi = phiRoot - lagAmp * grab * pow(s + 0.02, 1.25) * 0.9 - peekBend
                x += ds * cos(phi)
                y += ds * sin(phi)
            }
        }
        return LeafMesh(positions: positions, normals: Self.vertexNormals(positions: positions, indices: Self.leafIndices))
    }

    /// Area-weighted vertex normals, the way `BufferGeometry.computeVertexNormals` does it for an indexed mesh.
    static func vertexNormals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        func wide(_ v: SIMD3<Float>) -> SIMD3<Double> { SIMD3<Double>(Double(v.x), Double(v.y), Double(v.z)) }
        var sums = [SIMD3<Double>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            i += 3
            let pA = wide(positions[ia]), pB = wide(positions[ib]), pC = wide(positions[ic])
            let cb = pC - pB
            let ab = pA - pB
            // cb x ab
            let n = SIMD3<Double>(cb.y * ab.z - cb.z * ab.y, cb.z * ab.x - cb.x * ab.z, cb.x * ab.y - cb.y * ab.x)
            sums[ia] += n
            sums[ib] += n
            sums[ic] += n
        }
        return sums.map { v in
            let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            let d = length == 0 ? 1 : length
            return SIMD3<Float>(Float(v.x / d), Float(v.y / d), Float(v.z / d))
        }
    }

    // MARK: Page blocks

    /// Vertex layout: foot face (15 columns x 2), head face (15 x 2), then the 4 corners of the fore edge.
    static let blockFootBase = 0
    static let blockHeadBase = (BookDims.blockColumns + 1) * 2
    static let blockForeBase = (BookDims.blockColumns + 1) * 2 * 2

    static let blockIndices: [UInt32] = {
        let m = BookDims.blockColumns
        var out: [UInt32] = []
        for (base, facesFront) in [(blockFootBase, true), (blockHeadBase, false)] {
            for i in 0..<m {
                let a = UInt32(base + i * 2), b = a + 1, c = a + 2, e = a + 3
                if facesFront { out.append(contentsOf: [a, c, b, b, c, e]) } else { out.append(contentsOf: [a, b, c, b, e, c]) }
            }
        }
        let f = UInt32(blockForeBase)
        out.append(contentsOf: [f, f + 1, f + 2, f + 2, f + 1, f + 3])
        return out
    }()

    /// The page block of one side for a stack of height `h`. A block that is too thin to see is hidden and left blank.
    func block(height h: Double, side: Int) -> BlockMesh {
        let m = BookDims.blockColumns
        var positions = [SIMD3<Float>](repeating: .zero, count: BookDims.blockVertexCount)
        var uvs = [SIMD2<Float>](repeating: .zero, count: BookDims.blockVertexCount)
        for base in [Self.blockFootBase, Self.blockHeadBase] {
            for i in 0...m {
                for r in 0..<2 { uvs[base + i * 2 + r].x = Float(Double(i) / Double(m) * 4) }
            }
        }
        guard h > 1e-4 else {
            return BlockMesh(visible: false, scaleX: 1, positions: positions, uvs: uvs)
        }
        let w = BookDims.pageWidth - 0.008
        let d = (BookDims.pageHeight - 0.012) / 2
        let stripes = 90.0
        func topAt(_ i: Int) -> Double {
            let s = Double(i) / Double(m)
            return max(0.002, h - 0.0016 - BookDims.gutterDip * (1 - BookMath.smooth(0, 0.42, s)))
        }
        for (base, z) in [(Self.blockFootBase, d), (Self.blockHeadBase, -d)] {
            for i in 0...m {
                let x = 0.004 + Double(i) / Double(m) * w
                let top = topAt(i)
                positions[base + i * 2] = SIMD3<Float>(Float(x), 0, Float(z))
                positions[base + i * 2 + 1] = SIMD3<Float>(Float(x), Float(top), Float(z))
                uvs[base + i * 2].y = 0
                uvs[base + i * 2 + 1].y = Float(top * stripes)
            }
        }
        let top = topAt(m)
        let x = 0.004 + w
        let corners: [(Double, Double, Double, Double, Double)] = [
            (x, 0, -d, 0, 0), (x, 0, d, 4, 0), (x, top, -d, 0, top * stripes), (x, top, d, 4, top * stripes),
        ]
        for (k, c) in corners.enumerated() {
            positions[Self.blockForeBase + k] = SIMD3<Float>(Float(c.0), Float(c.1), Float(c.2))
            uvs[Self.blockForeBase + k] = SIMD2<Float>(Float(c.3), Float(c.4))
        }
        return BlockMesh(visible: true, scaleX: Double(side), positions: positions, uvs: uvs)
    }

    // MARK: Ribbon

    /// The ribbon lying down the gutter of the right-hand page and hanging over the foot of the book: 13 rows of 2 vertices.
    func ribbon() -> (visible: Bool, positions: [SIMD3<Float>]) {
        let rows = BookDims.ribbonRows
        let topY = max(restY(0).yr, BookDims.coverThickness + bulk * 0.5)
        let ph = BookDims.pageHeight
        var positions: [SIMD3<Float>] = []
        for r in 0..<rows {
            let t = Double(r) / Double(rows - 1)
            let z = BookMath.lerp(-ph * 0.46, ph * 0.5 + 0.16, t)
            let over = max(0, z - ph / 2)
            let y = over > 0
                ? BookMath.lerp(topY + 0.004, 0.0, BookMath.smooth(0, 0.16, over)) + 0.002
                : topY + 0.004
            for c in 0..<2 {
                positions.append(SIMD3<Float>(Float(0.02 + Double(c) * 0.014), Float(y), Float(z)))
            }
        }
        return (coverOpen > 0.6, positions)
    }
}
